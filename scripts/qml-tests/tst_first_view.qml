import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// FirstView and FrameLatch: the first view builds its parts in order to
// its cap before the first frame and the rest after it, an unknown cap
// builds nothing until it is known, a target builds
// with one cap of room after it, `ensure` builds a deferred part now with
// every part before it, laid out in the same turn, a block loading before
// that part, at its show or at a hide finishes rather than aborts, unless the view has
// left its window, a hidden view takes no
// step, and a frame in flight
// at an arm does not fire the latch. A group of rows fills before the
// next group. A section in a block keeps the
// heading space it has in a plain Column.
Item {
    id: root
    width: 400
    height: 600

    Component {
        id: blockView
        FirstView {
            property alias blocks: blocks
            property int targetAt: -1
            width: 300
            cap: 250
            Repeater {
                id: blocks
                model: 12
                FirstView.Block {
                    required property int index
                    target: index === parent.targetAt
                    Rectangle { width: 300; height: 100 }
                }
            }
        }
    }

    Component {
        id: rowView
        FirstView {
            property alias rows: rows
            width: 300
            cap: 100
            FirstView.Rows {
                id: rows
                values: Array.from({ length: 50 }, (_, i) => ({ key: "row" + i }))
                objectProp: "key"
                Rectangle { required property var modelData; width: 300; height: 20 }
            }
        }
    }

    // Groups of rows in rows, as Key Hints lists binds under each plugin.
    Component {
        id: nestedView
        FirstView {
            property alias groups: groups
            width: 300
            cap: 100
            FirstView.Rows {
                id: groups
                values: ["a", "b", "c"]
                Column {
                    required property string modelData
                    property alias rows: rows
                    width: 300
                    Rectangle { width: 300; height: 10 }
                    FirstView.Rows {
                        id: rows
                        values: Array.from({ length: 6 }, (_, i) => i)
                        Rectangle { width: 300; height: 20 }
                    }
                }
            }
        }
    }

    // The same sections plain and in blocks.
    Component {
        id: plainSections
        Column {
            width: 300
            spacing: Theme.stack.group
            Section { title: "First"; Label { role: "body"; text: "One row" } }
            Section { title: "Second"; Label { role: "body"; text: "Another row" } }
        }
    }
    Component {
        id: blockSections
        FirstView {
            width: 300
            cap: 1000
            spacing: Theme.stack.group
            FirstView.Block { Section { title: "First"; Label { role: "body"; text: "One row" } } }
            FirstView.Block { Section { title: "Second"; Label { role: "body"; text: "Another row" } } }
        }
    }
    // Groups built as rows, the second behind the first frame, then a
    // plain section after them; and the same sections in a plain Column.
    Component {
        id: plainGroups
        Column {
            width: 300
            spacing: Theme.stack.group
            Section { title: "a"; Label { role: "body"; text: "Deep ink: gjpqy" } }
            Section { title: "b"; Rectangle { width: 300; height: 40 } }
            Section { title: "Last"; Label { role: "body"; text: "One row" } }
        }
    }
    Component {
        id: rowGroups
        FirstView {
            width: 300
            cap: 60
            spacing: Theme.stack.group
            FirstView.Rows {
                values: ["a", "b"]
                Section {
                    id: group
                    required property string modelData
                    title: modelData
                    Label { visible: group.modelData === "a"; role: "body"; text: "Deep ink: gjpqy" }
                    Rectangle { visible: group.modelData === "b"; width: 300; height: 40 }
                }
            }
            Section { title: "Last"; Label { role: "body"; text: "One row" } }
        }
    }
    // Keyed rows: a cap that builds all three, or two of twenty.
    Component {
        id: keyedView
        FirstView {
            property alias rows: rows
            property int length: 3
            width: 300
            FirstView.Rows {
                id: rows
                values: Array.from({ length: parent.length }, (_, i) => ({ key: "row" + i }))
                objectProp: "key"
                Rectangle { required property var modelData; width: 300; height: 20 }
            }
        }
    }
    // The same rows unkeyed, each value a string, as Power's idle timeline
    // lists its stages.
    Component {
        id: unkeyedView
        FirstView {
            property alias rows: rows
            property int length: 3
            width: 300
            FirstView.Rows {
                id: rows
                values: Array.from({ length: parent.length }, (_, i) => "row" + i)
                Rectangle { required property var modelData; width: 300; height: 20 }
            }
        }
    }
    // The middle block fails to incubate: its content leaves a required
    // property unset.
    Component {
        id: failingView
        FirstView {
            property alias last: last
            width: 300
            cap: 100
            FirstView.Block { Rectangle { width: 300; height: 100 } }
            FirstView.Block { Item { required property int unset; width: 300; height: 100 } }
            FirstView.Block { id: last; Rectangle { width: 300; height: 100 } }
        }
    }
    Component {
        id: emptyView
        FirstView { width: 300; cap: 100 }
    }
    // Blocks heavy enough that each loads over several incubation slices.
    Component {
        id: heavyView
        FirstView {
            id: heavy
            property alias blocks: blocks
            property int hiddenAt: -1
            width: 300
            cap: 150
            Repeater {
                id: blocks
                model: 6
                FirstView.Block {
                    required property int index
                    visible: index !== heavy.hiddenAt
                    Item {
                        width: 300
                        height: 100
                        Repeater { model: 1500; Text { text: "row " + index } }
                    }
                }
            }
        }
    }

    UnitCase {
        name: "first_view"
        when: windowShown

        function builtBlocks(view) {
            const out = [];
            for (let i = 0; i < view.blocks.count; i++) out.push(view.blocks.itemAt(i).item !== null);
            return out;
        }
        function count(flags) { return flags.filter(Boolean).length; }

        function test_the_first_view_builds_to_its_cap_and_the_rest_after_it() {
            const view = createTemporaryObject(blockView, root);
            // Each block is 100 tall: the third reaches the 250 cap.
            compare(builtBlocks(view), [true, true, true, false, false, false, false, false, false, false, false, false]);
            compare(view.settled, false);
            tryCompare(view, "settled", true, 5000, "the rest builds after the first frame");
            compare(count(builtBlocks(view)), 12);
            // `settled` answers what is built, not where it stands: a block
            // a step loads is laid out by the Column's next polish
            // (https://doc.qt.io/qt-6/qml-qtquick-column.html#forceLayout-method).
            tryCompare(view, "height", 1200, 5000, "every block lands in the column");
        }

        function test_a_target_builds_with_one_cap_after_it() {
            const view = blockView.createObject(root, { targetAt: 5 });
            // Block 5 ends at 600; one cap past it is 850, which block 8 reaches.
            compare(count(builtBlocks(view)), 9);
            compare(builtBlocks(view)[8], true);
            compare(builtBlocks(view)[9], false);
            view.destroy();
        }

        function test_an_unknown_room_builds_once_it_is_known() {
            const view = blockView.createObject(root, { cap: Infinity });
            compare(count(builtBlocks(view)), 0, "no room, no first view past a target");
            view.cap = 250;
            compare(count(builtBlocks(view)), 3);
            view.destroy();
        }

        function test_a_group_fills_its_rows_before_the_next_group() {
            const view = createTemporaryObject(nestedView, root);
            // A 10-tall heading, then 20-tall rows: the first group's
            // heading and five rows reach the 100 cap.
            compare(view.groups.count, 1, "the next group waits for the first one's rows");
            compare(view.groups.itemAt(0).rows.count, 5);
        }

        function test_ensure_builds_a_deferred_part_with_every_part_before_it() {
            const view = createTemporaryObject(blockView, root);
            const block = view.blocks.itemAt(10);
            const item = view.ensure(block);
            verify(item !== null, "ensure answers the built item");
            compare(item, block.item);
            compare(builtBlocks(view).slice(0, 11), Array(11).fill(true));
            // Read in the same turn, before any polish: a reveal or a
            // pointer read finds the item where the page draws it.
            compare(item.mapToItem(view, 0, 0).y, 1000, "the ensured block stands below the ten before it");
        }

        function test_rows_build_to_the_cap_then_step() {
            const view = createTemporaryObject(rowView, root);
            const rows = view.rows;
            compare(rows.count, 5, "five 20-tall rows reach the 100 cap");
            const row = view.ensure(rows, 30);
            verify(row !== null);
            compare(rows.count, 31);
            compare(row.modelData.key, "row30");
            compare(row.mapToItem(view, 0, 0).y, 600, "the ensured row stands below the thirty before it");
            tryCompare(view, "settled", true, 5000);
            compare(rows.count, 50);
        }

        function test_a_row_target_builds_with_one_cap_after_it() {
            const targeted = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nFirstView { property alias rows: rows; width: 300; cap: 100\n"
                + " FirstView.Rows { id: rows; target: 20; values: Array.from({ length: 50 }, (_, i) => i)\n"
                + "  Rectangle { width: 300; height: 20 } } }", root);
            // Row 20 ends at 420; one cap past it is 520, which row 25 reaches.
            compare(targeted.rows.count, 26);
            targeted.destroy();
        }

        // A value inserted before a built row, after the first frame,
        // keeps that row's delegate: the row a user is editing or focusing
        // survives a republish of its list.
        function test_an_insertion_keeps_every_built_row_data() {
            return [
                { tag: "keyed, every row built", keyed: true, length: 3, cap: 1000, built: 3, at: 1, last: 2 },
                { tag: "keyed, some rows built", keyed: true, length: 20, cap: 40, built: 2, at: 1, last: 1 },
                { tag: "unkeyed, every row built", keyed: false, length: 3, cap: 1000, built: 3, at: 1, last: 2 },
                { tag: "unkeyed, some rows built", keyed: false, length: 20, cap: 40, built: 2, at: 1, last: 1 }
            ];
        }

        function test_an_insertion_keeps_every_built_row(data) {
            const view = createTemporaryObject(data.keyed ? keyedView : unkeyedView, root, { length: data.length, cap: data.cap });
            // Stop the steps once the first frame swaps, so the rows built
            // stay those of the first view.
            const hide = () => {
                view.latch.fired.disconnect(hide);
                view.visible = false;
            };
            view.latch.fired.connect(hide);
            tryVerify(() => !view.visible, 5000, "the first frame swapped");
            compare(view.rows.count, data.built);
            const kept = view.rows.itemAt(data.last);
            const values = view.rows.values.slice();
            values.splice(data.at, 0, data.keyed ? { key: "new" } : "new");
            view.rows.values = values;
            compare(view.rows.itemAt(data.last + 1), kept, "the built row keeps its delegate");
            const inserted = view.rows.itemAt(data.at).modelData;
            compare(data.keyed ? inserted.key : inserted, "new");
        }

        function test_ensureAll_builds_every_shown_part_and_leaves_a_hidden_one() {
            const view = createTemporaryObject(heavyView, root, { hiddenAt: 3 });
            view.ensureAll();
            verify(!view.settled, "a hidden part is left");
            const built = [];
            for (let i = 0; i < view.blocks.count; i++) built.push(view.blocks.itemAt(i).item !== null);
            compare(built, [true, true, true, false, true, true]);
            compare(view.blocks.itemAt(5).item.mapToItem(view, 0, 0).y, 400, "every built block is laid out in the same turn");
        }

        // expected-log: Required property unset was not initialized -- the planted block content
        // expected-log: first-view: a block failed to load -- the error the failed block reports
        function test_a_block_that_fails_to_load_lets_the_rest_build() {
            const view = createTemporaryObject(failingView, root);
            compare(view.last.item, null, "the last block stands past the first view");
            tryCompare(view, "settled", true, 5000, "the steps go on past the failed block");
            verify(view.last.item !== null);
        }

        function test_a_hidden_view_takes_no_step() {
            const view = createTemporaryObject(blockView, root);
            // Hide between the latch and the step it queues, as the core
            // hides an instance before draining its lifetime.
            const hide = () => {
                view.latch.fired.disconnect(hide);
                view.visible = false;
            };
            view.latch.fired.connect(hide);
            tryVerify(() => !view.visible, 5000, "the first frame swapped");
            for (let i = 0; i < 3; i++) verify(renderedFrame(root));
            compare(count(builtBlocks(view)), 3, "a hidden view builds nothing more");
            view.visible = true;
            tryCompare(view, "settled", true, 5000, "the view resumes once shown");
        }

        // The first block whose asynchronous load is in flight, before the
        // last block.
        // tryVerify polls every 50 ms, longer than a block can take to
        // load, so this polls each turn up to a deadline.
        function loadInFlight(view) {
            const deadline = Date.now() + 5000;
            while (Date.now() < deadline) {
                for (let i = 0; i < view.blocks.count - 1; i++)
                    if (view.blocks.itemAt(i).status === Loader.Loading) return i;
                wait(1);
            }
            fail("a block loads after the first frame");
        }

        function test_ensure_finishes_a_load_in_flight_before_its_part() {
            const view = createTemporaryObject(heavyView, root);
            const at = loadInFlight(view);
            const last = view.blocks.itemAt(view.blocks.count - 1);
            const item = view.ensure(last);
            compare(view.blocks.itemAt(at).status, Loader.Ready, "the block loading above it finished");
            const y = item.mapToItem(view, 0, 0).y;
            compare(y, 500, "the ensured block stands below the five before it");
            tryCompare(view, "settled", true, 5000);
            compare(item.mapToItem(view, 0, 0).y, y, "nothing above the ensured block grows after it");
        }

        function test_a_hide_finishes_a_load_in_flight() {
            const view = createTemporaryObject(heavyView, root);
            const at = loadInFlight(view);
            const block = view.blocks.itemAt(at);
            view.visible = false;
            compare(block.status, Loader.Ready, "the hide finishes the load, never aborts it");
            verify(block.item !== null);
            compare(view.blocks.itemAt(at + 1).item, null, "the hide starts no further load");
        }

        function test_a_block_shown_while_it_loads_builds_at_once() {
            // Blocks 0 and 1 fill the first view; the steps load the hidden
            // block 2 first, as they load a hidden tab's page.
            const view = createTemporaryObject(heavyView, root, { hiddenAt: 2 });
            compare(loadInFlight(view), 2);
            const block = view.blocks.itemAt(2);
            view.hiddenAt = -1;
            compare(block.status, Loader.Ready, "a tab's page reads built when its tab shows");
            verify(block.item !== null);
        }

        function test_a_view_out_of_its_window_builds_nothing_at_a_hide() {
            const view = createTemporaryObject(heavyView, root);
            const at = loadInFlight(view);
            const block = view.blocks.itemAt(at);
            // As a window's content item lets its items go before the
            // host destroys the instance.
            view.parent = null;
            view.visible = false;
            compare(block.status, Loader.Loading, "the load is left to its Loader");
            compare(block.item, null);
        }

        function test_a_frame_in_flight_at_the_arm_does_not_fire_the_latch() {
            // FrameLatch is internal to qs.Ui: drive a view's own latch,
            // once its first arm has fired.
            const view = createTemporaryObject(emptyView, root);
            tryVerify(() => !view.latch.armed, 5000, "the first arm fired");
            const latch = view.latch;
            const window = root.Window.window;
            let armed = false;
            let startsAfterArm = 0;
            let firedAfter = -1;
            // Arm between a frame's sync and its swap: that frame started
            // before the arm. The latch may fire only on the swap of a frame
            // whose start came after the arm, whichever handler runs first.
            const onSync = () => {
                if (armed) return;
                armed = true;
                latch.arm();
            };
            const onStart = () => { if (armed) startsAfterArm++; };
            window.afterSynchronizing.connect(onSync);
            window.afterAnimating.connect(onStart);
            latch.fired.connect(() => { firedAfter = startsAfterArm; });
            window.update();
            tryVerify(() => firedAfter !== -1, 5000, "the latch fires");
            window.afterSynchronizing.disconnect(onSync);
            window.afterAnimating.disconnect(onStart);
            verify(firedAfter >= 1, "the latch fires on a frame started after the arm");
        }

        // A Repeater stacks a row it builds into place with no change of
        // its parent's children, so a heading after it must read the row
        // laid out before it, not the one that stood there first.
        function test_a_heading_after_rows_built_later_keeps_its_heading_space() {
            const plain = createTemporaryObject(plainGroups, root);
            const view = createTemporaryObject(rowGroups, root);
            compare(view.settled, false, "the second group builds behind the first frame");
            tryCompare(view, "settled", true, 5000);
            verify(waitForPolish(plain));
            verify(waitForPolish(view));
            const last = view.children.filter(child => child instanceof Section && child.title === "Last")[0];
            compare(last.y, plain.children[2].y);
            compare(view.height, plain.height);
        }

        function test_a_section_in_a_block_keeps_its_heading_space() {
            const plain = createTemporaryObject(plainSections, root);
            const blocked = createTemporaryObject(blockSections, root);
            verify(waitForPolish(plain));
            verify(waitForPolish(blocked));
            const second = blocked.children.filter(child => child instanceof Loader)[1].item;
            compare(second.y + second.parent.y, plain.children[1].y);
            compare(blocked.height, plain.height);
        }
    }
}
