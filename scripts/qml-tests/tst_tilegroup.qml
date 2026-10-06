import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// TileGroup: the tiles share the control's width equally, a click or the
// left and right keys choose a tile and `activated` fires for a change the
// user made, a tile marked unavailable is disabled and passed over, and
// the ring shows on the chosen tile for keyboard focus alone, in a colour
// its accent border is not.
Item {
    id: root
    width: 500
    height: 300

    TileGroup {
        id: control
        width: 400
        model: [
            { text: "A", icon: "scan" },
            { text: "Window", icon: "app-window" },
            { text: "Off", icon: "monitor", available: false },
            { text: "All displays", icon: "monitor-check" }
        ]
    }
    TileGroup {
        id: unsized
        y: 100
        model: [{ text: "A", icon: "scan" }, { text: "All displays", icon: "monitor-check" }]
    }
    Button { id: after; text: "Next"; y: 200 }
    SignalSpy { id: activations; target: control; signalName: "activated" }

    TestCase {
        name: "tilegroup"
        when: windowShown

        function init() {
            UnitTheme.reset();
            control.currentIndex = 0;
            control.focus = false;
            after.focus = false;
            activations.clear();
        }

        function tile(group, index) { return group.contentItem.children[index]; }
        function ring(index) { return tile(control, index).background.children[0]; }

        function test_tiles_share_the_width_equally() {
            const share = (control.width - 3 * Theme.tileGroup.gap) / 4;
            verify(tile(control, 3).implicitWidth > tile(control, 0).implicitWidth, "the captions differ in width");
            for (let i = 0; i < 4; i++) {
                compare(tile(control, i).width, share);
                tryCompare(tile(control, i), "x", i * (share + Theme.tileGroup.gap));
            }
            compare(tile(unsized, 0).width, tile(unsized, 1).width);
            compare(unsized.width, 2 * tile(unsized, 1).implicitWidth + Theme.tileGroup.gap);
        }

        function test_keys_choose_and_skip_an_unavailable_tile() {
            control.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Right);
            compare(control.currentIndex, 1);
            compare(activations.count, 1);
            compare(activations.signalArguments[0][0], 1);
            keyClick(Qt.Key_Right);
            compare(control.currentIndex, 3);
            keyClick(Qt.Key_Right);
            compare(control.currentIndex, 3);
            keyClick(Qt.Key_Left);
            compare(control.currentIndex, 1);
            keyClick(Qt.Key_Home);
            compare(control.currentIndex, 0);
            compare(activations.count, 4);
        }

        function test_an_unavailable_tile_is_disabled() {
            compare(tile(control, 2).enabled, false);
            compare(tile(control, 1).enabled, true);
            mouseClick(tile(control, 2));
            compare(control.currentIndex, 0);
            compare(activations.count, 0);
        }

        function test_click_chooses_and_takes_the_keys() {
            after.forceActiveFocus();
            mouseClick(tile(control, 1));
            compare(control.currentIndex, 1);
            compare(activations.count, 1);
            compare(control.activeFocus, true);
            mouseClick(tile(control, 1));
            compare(activations.count, 1);
            tryCompare(tile(control, 1).background, "color", Qt.color(Theme.tileGroup.selectedBackground));
            keyClick(Qt.Key_Right);
            compare(control.currentIndex, 3);
        }

        // The ring is the chosen tile's, for Tab focus and not for a
        // click. Its colour is not the chosen tile's accent border, on the
        // shipped tint and on an opaque fill the ring's own colour shows
        // on, where no contrast switch steps in.
        function test_ring_shows_on_the_chosen_tile_for_keyboard_focus() {
            mouseClick(tile(control, 1));
            compare(control.activeFocus, true);
            verify(!ring(0).visible && !ring(1).visible, "a click shows no ring");
            control.focus = false;
            control.forceActiveFocus(Qt.TabFocusReason);
            verify(ring(1).visible, "Tab focus rings the chosen tile");
            verify(!ring(0).visible && !ring(3).visible, "other tiles draw no ring");
            const border = tile(control, 1).background.border.color;
            verify(!Qt.colorEqual(ring(1).border.color, border), "the ring differs from the accent border");
            compare(UnitTheme.override({ tileGroup: { selectedBackground: "#101010" } }), "ok");
            tryCompare(tile(control, 1).background, "color", Qt.color("#101010"));
            verify(!Qt.colorEqual(ring(1).border.color, tile(control, 1).background.border.color), "the ring differs from the accent border on an opaque fill");
            control.focus = false;
            verify(!ring(1).visible, "the ring leaves with focus");
        }

        function test_one_tab_stop() {
            root.forceActiveFocus();
            keyClick(Qt.Key_Tab);
            compare(control.activeFocus, true);
            for (let i = 0; i < 4; i++) verify(!tile(control, i).activeFocus, "no tile holds focus");
            keyClick(Qt.Key_Tab);
            verify(!control.activeFocus, "the next Tab leaves the group");
        }
    }
}
