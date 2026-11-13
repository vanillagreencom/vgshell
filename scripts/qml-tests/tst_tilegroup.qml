import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// TileGroup: the tiles share the control's width equally, a click or the
// left and right keys choose a tile and `activated` fires for a change the
// user made, a tile marked unavailable is disabled and passed over, the
// ring shows on the chosen tile for keyboard focus alone, in a colour its
// accent border is not, and a caption wider than its tile wraps whole.
Item {
    id: root
    width: 500
    height: 400

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
    // The Power flyout's three profile tiles, across its content width.
    TileGroup {
        id: flyout
        y: 250
        width: Theme.size.panel.md - 2 * Theme.inset.panel
        model: [{ text: "Power saver", icon: "leaf" }, { text: "Balanced", icon: "gauge" }, { text: "Performance", icon: "zap" }]
    }
    TextMetrics { id: oneLine }
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
        function glyph(group, index) { return tile(group, index).contentItem.children[0]; }
        function caption(group, index) { return tile(group, index).contentItem.children[1]; }

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

        // A theme's larger text makes "Power saver" wider than one line of
        // its tile, as a wider interface font does at the shipped size. It
        // breaks at its space and "Performance" inside the word, neither
        // cut; every tile keeps the group's height with its caption inside,
        // and the icons share one line.
        function test_a_caption_wider_than_its_tile_wraps_whole() {
            compare(UnitTheme.override({ font: { size: 20 } }), "ok");
            const saver = caption(flyout, 0);
            oneLine.font = saver.font;
            oneLine.text = "Power saver";
            verify(oneLine.advanceWidth > saver.width, "the caption is wider than one line of its tile");
            for (let i = 0; i < 3; i++) {
                const shown = caption(flyout, i);
                verify(!shown.truncated, flyout.model[i].text + " is not cut");
                compare(tile(flyout, i).height, flyout.height);
                verify(shown.mapToItem(tile(flyout, i), 0, shown.height).y <= tile(flyout, i).height, flyout.model[i].text + " ends inside its tile");
                compare(glyph(flyout, i).y, glyph(flyout, 0).y);
            }
            compare(saver.text.split("\n"), ["Power", "saver"]);
            compare(tile(flyout, 0).Accessible.name, "Power saver");
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
