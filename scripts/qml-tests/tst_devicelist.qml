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
// while the list holds the keyboard; a change to the rows keeps the item
// of each row whose key stays and the keyboard on its row, wherever the
// row moves, and a row a change moves from under a resting pointer hands
// the plate to the selection; the selection follows its row only while
// the user chose it or the list holds the keyboard, a choice ends when its
// row leaves, and else the selection keeps its place; a row's
// `secondaryTone` reaches its DeviceRow; a row's icon actions draw after
// its action in order, take no Tab stop, emit `chose` on a press, lead its
// menu, which Shift+F10 opens, and draw no overflow button when the menu
// holds nothing else, nor anything on a busy row, and keep their buttons
// when a label changes; a locked row's icon takes no press; a hover over the row at a scroll area's edge moves the plate
// and neither the keyboard nor the page, while the arrows still reveal. A
// list given a `disabledReason` keeps its selected row a Tab stop, takes
// no click and no key, on a row or its action, moves no selection under
// the pointer, offers no overflow menu, draws its rows' content faded
// under a full-strength ring, and shows the reason on hover and on
// keyboard focus; an empty reason leaves it as it was. A row that opens
// draws a chevron; under a reason it still takes its click and its keys
// and draws unfaded, the arrows still move, and the list's other rows stay
// locked, the reason opening on their keyboard focus alone. The tooltip
// waits on `tooltip.delay` in real time, so this proves its wiring.
Item {
    id: root
    width: 480
    height: 600

    readonly property string reason: "Only the administrator can change Tailscale."
    // The label of row b's copy action, which a case's trigger changes.
    property string copyLabel: "Copy"

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
            iconActionsOf: row => row.key === "a" ? [{ key: "connect", iconName: "terminal", label: "Connect in terminal" }] : []
        }
    }
    Component { id: spyComponent; SignalSpy {} }
    // A locked list whose first and last rows open views of their own.
    Component {
        id: mixedList
        DeviceList {
            y: 320
            width: 420
            disabledReason: root.reason
            rows: [
                { key: "sweden", text: "Sweden", secondary: "3 cities", iconName: "map-pin", opens: true },
                { key: "zurich", text: "Switzerland", secondary: "Zurich", iconName: "map-pin" },
                { key: "usa", text: "USA", secondary: "9 cities", iconName: "map-pin", opens: true }
            ]
        }
    }
    // A list of its own, as the Tailscale exit node chooser's top list.
    Component {
        id: choiceList
        DeviceList {
            y: 320
            width: 420
        }
    }
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

    UnitCase {
        name: "devicelist"
        when: windowShown

        function trailing(row) { return row.contentItem.children[2].children; }
        function spinnerOf(row) { return trailing(row)[1].children[0]; }
        function actionOf(row) { return trailing(row)[1].children[1]; }
        // The menu hangs from the overflow button, or from the actions
        // while the button is hidden.
        function menuOf(row) { return trailing(row)[1].children.concat(trailing(row)[2].children).find(child => child.triggerCurrent !== undefined); }
        function iconsOf(row) { return trailing(row)[1].children.filter(child => child.label !== undefined && child.objectName.indexOf("/") !== -1); }
        function leftOf(item) { return item.mapToItem(list, 0, 0).x; }
        function args(spy, index) { return Array.from(spy.signalArguments[index]); }
        readonly property var icons: [{ key: "connect", iconName: "terminal", label: "Connect in terminal" }, { key: "copy", iconName: "copy", label: "Copy" }]

        function init() {
            UnitTheme.reset();
            list.rows = root.three;
            list.actionOf = row => row.key === "a" ? { text: "Disconnect" } : null;
            list.menuOf = row => row.key === "a" ? [{ key: "rename", text: "Rename" }, { key: "forget", text: "Forget" }] : [];
            list.iconActionsOf = row => [];
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

        function test_tab_reaches_the_selected_rows_action_and_overflow() {
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

        function test_only_the_selected_row_is_a_tab_stop_data() {
            return [
                { tag: "ready", initiallyChecking: false, checkAgain: false, chooseSecond: false, index: 0, key: "a1b2" },
                { tag: "initially checking then ready", initiallyChecking: true, checkAgain: false, chooseSecond: false, index: 0, key: "a1b2" },
                { tag: "ready checking ready outside", initiallyChecking: false, checkAgain: true, chooseSecond: false, index: 0, key: "a1b2" },
                { tag: "second choice retained through checking", initiallyChecking: false, checkAgain: true, chooseSecond: true, index: 1, key: "c3d4" }
            ];
        }
        function test_only_the_selected_row_is_a_tab_stop(data) {
            const made = createTemporaryObject(choiceList, root, {
                rows: [
                    { key: "a1b2", text: "amelie@example.com" },
                    { key: "c3d4", text: "amelie@example.org" }
                ],
                disabledReason: data.initiallyChecking ? root.reason : ""
            });
            tryVerify(() => made.rowAt(1) !== null && made.rowAt(1).y >= made.rowAt(0).y + made.rowAt(0).height, 1000, "the account rows are laid out");
            // The existing list's overflow precedes this separate list;
            // Scan follows it when the window's Tab chain wraps.
            const preceding = trailing(list.rowAt(0))[2];
            if (data.chooseSecond) {
                made.focusCurrent(Qt.TabFocusReason);
                tryCompare(made.rowAt(0), "activeFocus", true);
                keyClick(Qt.Key_Down);
                compare(made.current, 1, "Down deliberately chooses the second account");
                compare(made.rowAt(1).activeFocus, true);
            }
            preceding.forceActiveFocus(Qt.TabFocusReason);
            const trace = [];
            function snapshot(stage) {
                const state = {
                    stage: stage, current: made.current, currentKey: made.currentKey,
                    selectedKey: made.selectedKey, chosenByUser: made.chosenByUser,
                    listActiveFocus: made.activeFocus, precedingActiveFocus: preceding.activeFocus,
                    afterActiveFocus: before.activeFocus,
                    focusText: root.Window.window.activeFocusItem === null ? null : root.Window.window.activeFocusItem.text,
                    rows: [0, 1].map(index => {
                        const row = made.rowAt(index);
                        return { key: row.key, text: row.text, selected: row.selected,
                            locked: row.locked, activeFocusOnTab: row.activeFocusOnTab,
                            focusPolicy: row.focusPolicy, policyHasTab: (row.focusPolicy & Qt.TabFocus) !== 0,
                            focus: row.focus, activeFocus: row.activeFocus };
                    })
                };
                trace.push(state);
                return state;
            }
            const states = [snapshot(data.initiallyChecking ? "initial-checking" : "initial-ready")];
            if (data.checkAgain) {
                made.disabledReason = root.reason;
                tryCompare(made.lock, "locked", true);
                states.push(snapshot("checking-outside"));
            }
            if (data.initiallyChecking || data.checkAgain) {
                made.disabledReason = "";
                tryCompare(made.lock, "locked", false);
                states.push(snapshot("ready-outside"));
            }
            keyClick(Qt.Key_Tab);
            const entered = snapshot("entered");
            keyClick(Qt.Key_Tab);
            const left = snapshot("one-tab-after-entry");
            console.info("devicelist-tab-trace " + JSON.stringify({ tag: data.tag, qt: UnitQt.VERSION, states: trace }));

            // Qt's focusPolicy setter also writes activeFocusOnTab. Read
            // both flags, then assert the composite's contract rather than
            // declaration order: Qt 6.12.0 qquickitem.cpp setFocusPolicy.
            for (const state of states) {
                compare(state.current, data.index, state.stage + ": checking keeps the selected position");
                compare(state.selectedKey, data.key, state.stage + ": checking keeps the selected key");
                compare(state.chosenByUser, data.chooseSecond, state.stage + ": checking invents no user choice");
                compare(state.listActiveFocus, false, state.stage + ": focus stays outside the list");
                compare(state.precedingActiveFocus, true, state.stage + ": focus stays on the preceding control");
                for (let index = 0; index < 2; index++)
                    compare(state.rows[index].activeFocusOnTab, index === data.index, state.stage + ": only the selected row takes Tab: " + state.rows[index].key);
            }
            compare(entered.rows[data.index].activeFocus, true, "Tab enters the exact selected account: " + data.key);
            compare(entered.current, data.index, "Tab keeps the selected position");
            compare(entered.selectedKey, data.key, "Tab keeps the selected key");
            compare(entered.rows[1 - data.index].activeFocus, false, "Tab never enters the other account");
            compare(left.afterActiveFocus, true, "one Tab leaves the account list for Scan");
            compare(left.listActiveFocus, false, "no second account stop follows the selected row");
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

        function test_icon_actions_draw_after_the_action_and_choose() {
            list.iconActionsOf = row => row.key === "a" ? icons : row.key === "b" ? icons.slice(1) : [];
            renderedFrame(list);
            const first = iconsOf(list.rowAt(0));
            compare(first.map(icon => [icon.iconName, icon.label, icon.tooltip, icon.visible]),
                [["terminal", "Connect in terminal", "Connect in terminal", true], ["copy", "Copy", "Copy", true]]);
            verify(leftOf(first[0]) > leftOf(actionOf(list.rowAt(0))), "the icons follow the row's action");
            verify(leftOf(first[1]) > leftOf(first[0]), "the icons draw in their order");
            compare(iconsOf(list.rowAt(2)).length, 0, "a row with no icon actions draws none");
            mouseClick(first[0]);
            compare(chose.count, 1);
            compare(args(chose, 0), ["a", "connect"]);
            mouseClick(iconsOf(list.rowAt(1))[0]);
            compare(args(chose, 1), ["b", "copy"]);
            compare(acted.count, 0, "an icon press runs no row action");
        }

        function test_icon_actions_take_no_tab_stop() {
            list.iconActionsOf = row => row.key === "a" ? icons : [];
            for (const icon of iconsOf(list.rowAt(0))) compare(icon.focusPolicy, Qt.NoFocus);
            keyClick(Qt.Key_Tab);
            tryCompare(list.rowAt(0), "activeFocus", true);
            keyClick(Qt.Key_Tab);
            compare(actionOf(list.rowAt(0)).activeFocus, true, "Tab moves from the row to its action");
            keyClick(Qt.Key_Tab);
            compare(trailing(list.rowAt(0))[2].activeFocus, true, "Tab moves from the action past the icons to the overflow button");
        }

        function test_the_menu_reaches_each_icon_action_first() {
            list.iconActionsOf = row => row.key === "a" || row.key === "b" ? icons : [];
            compare(menuOf(list.rowAt(0)).items().map(item => [item.text, item.iconName]),
                [["Connect in terminal", "terminal"], ["Copy", "copy"], ["Rename", ""], ["Forget", ""]]);
            verify(trailing(list.rowAt(0))[2].visible, "a menu with entries of its own draws the overflow button");
            menuOf(list.rowAt(0)).items()[0].triggered();
            compare(args(chose, 0), ["a", "connect"]);
            // Row b's menu holds only its icons: no button repeats them, and
            // the menu keys still open them.
            const row = list.rowAt(1);
            verify(!trailing(row)[2].visible, "a menu of the icons alone draws an overflow button");
            list.current = 1;
            focusList();
            keyClick(Qt.Key_F10, Qt.ShiftModifier);
            const menu = menuOf(row);
            tryCompare(menu, "opened", true);
            verify(menu.anchorItem.visible, "the menu hangs from a drawn item");
            compare(menu.items().map(item => item.text), ["Connect in terminal", "Copy"]);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            tryCompare(menu, "opened", false);
            compare(args(chose, 1), ["b", "copy"]);
        }

        // A changed label, as a copy's Copied, keeps the button.
        function test_an_icon_action_keeps_its_button_when_its_label_changes() {
            list.iconActionsOf = row => row.key === "a" ? icons : [];
            const before = iconsOf(list.rowAt(0))[1];
            list.iconActionsOf = row => row.key === "a" ? [icons[0], { key: "copy", iconName: "check", label: "Copied" }] : [];
            const after = iconsOf(list.rowAt(0))[1];
            verify(after === before, "the copy action keeps its button");
            compare([after.iconName, after.label], ["check", "Copied"]);
        }

        // A trigger that changes its own entry's label, as a copy's to
        // Copied, still closes the menu.
        function test_a_menu_entry_whose_label_its_trigger_changes_closes_the_menu() {
            list.iconActionsOf = row => row.key === "b" ? [{ key: "copy", iconName: "copy", label: root.copyLabel }] : [];
            const relabel = () => { root.copyLabel = "Copied"; };
            list.chose.connect(relabel);
            try {
                list.current = 1;
                focusList();
                keyClick(Qt.Key_F10, Qt.ShiftModifier);
                const menu = menuOf(list.rowAt(1));
                tryCompare(menu, "opened", true);
                keyClick(Qt.Key_Return);
                compare(args(chose, 0), ["b", "copy"]);
                tryCompare(menu, "opened", false);
                compare(iconsOf(list.rowAt(1))[0].label, "Copied");
                compare(menu.items()[0].text, "Copied");
            } finally {
                list.chose.disconnect(relabel);
                root.copyLabel = "Copy";
            }
        }

        // A key reopening after a trigger, as Copy and then Connect in
        // terminal, highlights the home entry again (VGS-2117). A list of
        // its own, so its menu's first opening is its first.
        function test_a_menu_reopened_by_key_after_a_trigger_highlights_its_home_entry() {
            const made = createTemporaryObject(choiceList, root, {
                rows: root.three,
                iconActionsOf: row => row.key === "b" ? [icons[0], { key: "copy", iconName: "copy", label: root.copyLabel }] : []
            });
            const spy = createTemporaryObject(spyComponent, root, { target: made, signalName: "chose" });
            const relabel = () => { root.copyLabel = "Copied"; };
            made.chose.connect(relabel);
            try {
                made.current = 1;
                const keyOpen = () => {
                    // The close hands the keys back through the compositor,
                    // which the stand-in only records.
                    root.Window.window.requestActivate();
                    made.focusCurrent(Qt.TabFocusReason);
                    tryCompare(made.rowAt(1), "activeFocus", true);
                    keyClick(Qt.Key_F10, Qt.ShiftModifier);
                };
                const menu = menuOf(made.rowAt(1));
                keyOpen();
                tryCompare(menu, "opened", true);
                compare(menu.currentIndex, 0, "a first key opening highlights the home entry");
                keyClick(Qt.Key_Down);
                keyClick(Qt.Key_Return);
                compare(args(spy, 0), ["b", "copy"]);
                tryCompare(menu, "opened", false);
                keyOpen();
                tryCompare(menu, "opened", true);
                verify(menu.homeIndex() !== -1, "the reopened menu holds a reachable entry");
                compare(menu.currentIndex, menu.homeIndex(), "a key reopening highlights the home entry");
                keyClick(Qt.Key_Return);
                compare(args(spy, 1), ["b", "connect"]);
            } finally {
                made.chose.disconnect(relabel);
                root.copyLabel = "Copy";
            }
        }

        function test_a_busy_row_draws_no_icon_actions() {
            list.rows = [{ key: "busy", text: "Earbuds", iconName: "headphones", busy: true }];
            list.iconActionsOf = row => icons;
            tryVerify(() => list.rowAt(0) !== null, 1000, "the row is built");
            compare(iconsOf(list.rowAt(0)).length, 0);
            verify(trailing(list.rowAt(0))[2].visible, "a busy row keeps its icon actions behind the overflow button");
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
            mouseClick(iconsOf(row)[0]);
            unchanged("click on an icon action");
            compare(iconsOf(row)[0].hovered, false, "a locked list's icon action draws hover");
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
            compare(menuOf(made.rowAt(0)).items().map(item => item.text), ["Connect in terminal", "Rename"]);
            mouseClick(made.rowAt(1), 20, made.rowAt(1).height / 2);
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], "b");
            keyClick(Qt.Key_Down);
            compare(made.current, 2);
        }

        function chevronOf(row) { return trailing(row)[1].children.find(child => child.name !== undefined && child.label === undefined); }

        // SearchRows rebuilds plain objects on each publish. Kept items
        // and focus survive, and moved items draw the new publication's text.
        function test_a_change_keeps_each_kept_row_and_the_keyboard_on_its_row_data() {
            return [
                { tag: "fresh search narrowing and widening", start: ["a", "b", "c", "d", "e"], chosen: "d", changes: [
                    { keys: ["b", "d", "e"], kept: ["b", "d", "e"] },
                    { keys: ["a", "b", "c", "d", "e"], kept: ["b", "d", "e"] }
                ] },
                { tag: "a moved device changes its text", start: ["a", "b", "c"], chosen: "c", changes: [
                    { keys: ["c", "a", "b"], kept: ["c", "a", "b"], text: { c: "Moved c" } }
                ] }
            ];
        }
        function test_a_change_keeps_each_kept_row_and_the_keyboard_on_its_row(data) {
            const rowsOf = (keys, text) => keys.map(key => ({ key: key, text: text && text[key] !== undefined ? text[key] : "Device " + key }));
            list.rows = rowsOf(data.start);
            list.current = data.start.indexOf(data.chosen);
            focusList();
            const kept = {};
            data.start.forEach((key, index) => { if (kept[key] === undefined) kept[key] = list.rowAt(index); });
            for (const change of data.changes) {
                list.rows = rowsOf(change.keys, change.text);
                compare(list.count, change.keys.length, "the publication leaves no extra rows");
                change.keys.forEach((key, index) => {
                    const row = list.rowAt(index);
                    compare(row.modelData, key, "the model holds a stable string key, not a payload");
                    if (change.kept.indexOf(key) !== -1) compare(row, kept[key], "a kept key keeps its item: " + key);
                    compare(row.text, change.text && change.text[key] !== undefined ? change.text[key] : "Device " + key, "the item draws its current data");
                });
                compare(list.currentKey, data.chosen, "the selection moves with its row");
                compare(kept[data.chosen].activeFocus, true, "the keyboard stays on its row");
            }
        }

        // A row a change moves from under a resting pointer hands the
        // plate to the selection, not to the row that comes under it.
        function test_a_change_that_moves_the_pointed_row_hands_the_plate_to_the_selection() {
            const rows = ["a", "b", "c", "d"].map(key => ({ key: key, text: "Device " + key }));
            list.rows = rows;
            // The user chose the first row, so the selection follows it.
            focusList();
            before.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => list.rowAt(3).y >= list.rowAt(2).y + list.rowAt(2).height, 1000, "the rows are laid out");
            const pointed = list.rowAt(2);
            mouseMove(pointed, 20, pointed.height / 2);
            mouseMove(pointed, 24, pointed.height / 2);
            compare(plateOf(list).placed, pointed, "the plate follows the pointer");
            list.rows = [{ key: "x", text: "Device x" }].concat(rows);
            tryVerify(() => list.rowAt(3) === pointed && pointed.y >= list.rowAt(2).y + list.rowAt(2).height, 1000, "the pointed row moved down");
            // compare() recurses over two different Items.
            tryVerify(() => plateOf(list).placed === list.rowAt(1), 1000, "the plate goes to the selection");
            compare(list.currentKey, "a");
            mouseMove(root, root.width - 1, 0);
        }

        function test_a_row_that_opens_draws_a_chevron() {
            list.rows = [
                { key: "sweden", text: "Sweden", secondary: "3 cities", iconName: "map-pin", opens: true },
                { key: "zurich", text: "Switzerland", secondary: "Zurich", iconName: "map-pin" }
            ];
            const chevron = chevronOf(list.rowAt(0));
            verify(chevron.visible, "the opening row draws its chevron");
            compare(chevron.name, "chevron-right");
            verify(!chevronOf(list.rowAt(1)).visible, "a row that chooses draws none");
        }

        // A row that opens a view changes nothing, so a reason leaves it
        // working; the list's other rows stay locked one by one.
        function test_a_locked_lists_row_that_opens_still_works() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            const made = createTemporaryObject(mixedList, root);
            tryVerify(() => made.rowAt(2).y >= made.rowAt(1).y + made.rowAt(1).height, 1000, "the rows are laid out");
            const spy = createTemporaryObject(spyComponent, root, { target: made, signalName: "acted" });
            const sweden = made.rowAt(0), zurich = made.rowAt(1);
            mouseClick(sweden, 20, sweden.height / 2);
            compare(spy.count, 1, "a click on the opening row acts");
            compare(spy.signalArguments[0][0], "sweden");
            mouseClick(zurich, 20, zurich.height / 2);
            compare(spy.count, 1, "a click on a locked row acts");
            compare(made.currentKey, "sweden", "a click on a locked row moves the selection");
            // The click left the row focused by the mouse, which draws no
            // ring and opens no reason; the keyboard takes it again by Tab.
            before.forceActiveFocus(Qt.TabFocusReason);
            made.focusCurrent(Qt.TabFocusReason);
            tryCompare(sweden, "activeFocus", true);
            compare(sweden.visualFocus, true);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(spy.count, 3, "Return and Space on the opening row act");
            compare(made.visualFocus, false, "the opening row opens no reason");
            tryCompare(sweden.contentItem, "opacity", 1);
            compare(zurich.contentItem.opacity, Theme.opacity.disabled, "a locked row draws faded");
            keyClick(Qt.Key_Down);
            compare(made.currentKey, "zurich", "the arrows move");
            compare(zurich.activeFocus, true);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(spy.count, 3, "a locked row takes no key");
            compare(made.visualFocus, true, "the keyboard on a locked row opens the reason");
            tryCompare(reasonTip(made), "opened", true);
            keyClick(Qt.Key_End);
            compare(made.currentKey, "usa");
            keyClick(Qt.Key_Return);
            compare(spy.count, 4);
            compare(spy.signalArguments[3][0], "usa");
            before.forceActiveFocus(Qt.TabFocusReason);
        }

        // A list with a row that opens shields no row, so a locked row's
        // icon action refuses its own press; the opening row's acts.
        function test_a_locked_lists_icon_action_chooses_only_on_a_row_that_opens() {
            const made = createTemporaryObject(mixedList, root);
            made.iconActionsOf = row => [{ key: "copy", iconName: "copy", label: "Copy" }];
            tryVerify(() => made.rowAt(2).y >= made.rowAt(1).y + made.rowAt(1).height, 1000, "the rows are laid out");
            const spy = createTemporaryObject(spyComponent, root, { target: made, signalName: "chose" });
            // Emitted, not clicked: the locked list's reason tooltip opens
            // under the pointer, and the guard is the icon's own.
            iconsOf(made.rowAt(1))[0].clicked();
            compare(spy.count, 0, "a locked row's icon chooses");
            mouseClick(iconsOf(made.rowAt(0))[0]);
            compare(spy.count, 1, "the opening row's icon chooses");
            compare(args(spy, 0), ["sweden", "copy"]);
            // The menu follows the same rule: the opening row's holds its
            // icon action, the locked row's holds none.
            compare(menuOf(made.rowAt(0)).items().map(item => item.text), ["Copy"]);
            compare(menuOf(made.rowAt(1)).items().length, 0, "a locked row's menu holds its icon action");
            menuOf(made.rowAt(0)).items()[0].triggered();
            compare(spy.count, 2, "the opening row's menu entry chooses");
            compare(args(spy, 1), ["sweden", "copy"]);
        }

        // Steps: "enter" hands the list the keyboard, "leave" takes it
        // away, "up" presses Up, and a list of keys sets the rows. The
        // third row is the exit node chooser's: the keys on Recommended,
        // Tailscale leaving and coming back, then a Tab into the list.
        function test_the_selection_follows_its_row_only_while_held_data() {
            return [
                { tag: "nobody chose it, so a row listed above takes it", start: ["none"], steps: [["recommended", "none"]], key: "recommended" },
                { tag: "the user's choice follows its row", start: ["recommended", "none"], steps: ["enter", "leave", ["own", "recommended", "none"]], key: "recommended" },
                { tag: "a choice whose row left is nobody's", start: ["recommended", "none"], steps: ["enter", "leave", ["none"], ["recommended", "none"]], key: "recommended" },
                { tag: "the row the list moved the keyboard to is nobody's choice", start: ["own", "recommended"], current: 1, steps: ["enter", ["own"], "leave", ["recommended", "own"]], key: "recommended" },
                { tag: "the keyboard stays on its row while the list holds it", start: ["recommended", "none"], steps: ["enter", ["none"], ["recommended", "none"]], key: "none" },
                { tag: "a key move is the user's choice", start: ["a", "b", "c"], current: 2, steps: ["enter", ["a", "b"], "up", "leave", ["x", "a", "b"]], key: "a" }
            ];
        }
        function test_the_selection_follows_its_row_only_while_held(data) {
            const rowsOf = keys => keys.map(key => ({ key: key, text: "Device " + key }));
            const made = createTemporaryObject(choiceList, root, { rows: rowsOf(data.start) });
            if (data.current !== undefined) made.current = data.current;
            for (const step of data.steps) {
                if (step === "enter") {
                    made.focusCurrent(Qt.TabFocusReason);
                    tryCompare(made.rowAt(made.current), "activeFocus", true);
                } else if (step === "leave") {
                    before.forceActiveFocus(Qt.TabFocusReason);
                    compare(made.activeFocus, false);
                } else if (step === "up") {
                    keyClick(Qt.Key_Up);
                } else {
                    made.rows = rowsOf(step);
                }
            }
            compare(made.currentKey, data.key);
            const row = made.rowAt(made.current);
            compare(row.text, "Device " + data.key, "the selected row is the row of its key");
            compare(row.activeFocusOnTab, true, "a Tab enters on the selected row");
            if (made.activeFocus) compare(row.activeFocus, true, "the keyboard is on the selected row");
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
