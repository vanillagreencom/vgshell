import QtQuick
import QtTest
import qs.Ui

// The touchpad scroll every view declares: a finger's delta moves the view
// GTK's 2.5 px per pixel, in whole pixels, on each axis the view scrolls
// and inside its bounds; a lift coasts the distance GTK's friction gives
// the swipe's last velocity, and fingers that rested first do not coast;
// a mouse wheel's notch stays Qt's; a view that fits takes no swipe, and
// no view takes a delta along an axis it does not scroll on; and a
// ScrollArea's content height does not count the area. The deltas are
// handed to `move` and `lift`, as the area's wheel handler hands them:
// QtTest sends no wheel event with a scroll phase, and
// scripts/smoke/rows/settings.sh sends a real swipe.
Item {
    id: root
    width: 400
    height: 400
    property real shrinkHeight: 300

    // Twice Qt's default deceleration, so a coast that read no deceleration
    // from its view would travel twice as far.
    Flickable {
        id: tall
        width: 100; height: 100; contentWidth: 100; contentHeight: 2000; flickDeceleration: 3000
        Rectangle { width: 100; height: 2000; color: "transparent" }
        TouchpadScroll { id: tallPad; view: tall }
    }
    Flickable {
        id: wide
        y: 110; width: 100; height: 50; contentWidth: 2000; contentHeight: 50
        Rectangle { width: 2000; height: 50; color: "transparent" }
        TouchpadScroll { id: widePad; view: wide }
    }
    // The same view with no touchpad scroll: Qt's own wheel step.
    Flickable {
        id: plain
        x: 110; width: 100; height: 100; contentWidth: 100; contentHeight: 2000
        Rectangle { width: 100; height: 2000; color: "transparent" }
    }
    ListView {
        id: list
        x: 220; width: 100; height: 100; model: 40
        delegate: Item { width: 100; height: 20 }
        TouchpadScroll { id: listPad; view: list }
    }
    // A list view that fits and stays interactive, as a tab strip does.
    ListView {
        id: strip
        x: 220; y: 220; width: 100; height: 20; orientation: ListView.Horizontal; model: 3
        delegate: Item { width: 20; height: 20 }
        TouchpadScroll { id: stripPad; view: strip }
    }
    ScrollArea { id: fits; x: 110; y: 110; width: 100; height: 100; Item { width: parent.width; height: 40 } }
    ScrollArea { id: shrinks; x: 220; y: 110; width: 100; height: 100; Item { width: parent.width; height: root.shrinkHeight } }

    function padOf(area) {
        return area.contentItem.children.find(child => child.view === area);
    }

    TestCase {
        name: "touchpadscroll"
        when: windowShown

        function init() {
            for (const view of [tall, wide, plain, list]) {
                view.cancelFlick();
                view.contentX = 0;
                view.contentY = 0;
            }
            for (const pad of [tallPad, widePad, listPad, stripPad]) pad.lift(0);
            root.shrinkHeight = 300;
            shrinks.contentY = 0;
        }

        function test_a_delta_moves_the_view_two_and_a_half_pixels_per_pixel() {
            tallPad.move(0, 40, 1000);
            compare(tall.contentY, 100);
            tallPad.move(0, -16, 1010);
            compare(tall.contentY, 60);
            listPad.move(0, 40, 1000);
            compare(list.contentY, 100, "a list view moves the same");
        }

        function test_a_view_stays_on_whole_pixels_and_loses_no_fraction() {
            const seen = [];
            for (let i = 0; i < 4; i++) {
                tallPad.move(0, 1, 1000 + i);
                seen.push(tall.contentY);
            }
            compare(seen, [3, 5, 8, 10]);
        }

        function test_a_delta_stops_at_the_bounds() {
            tallPad.move(0, -40, 1000);
            compare(tall.contentY, 0, "the start");
            tallPad.move(0, 5000, 1010);
            compare(tall.contentY, 1900, "the end");
            compare(tall.contentX, 0, "an axis with no room stays");
        }

        function test_a_horizontal_view_moves_along_its_own_axis() {
            widePad.move(40, 0, 1000);
            compare(wide.contentX, 100);
            compare(wide.contentY, 0);
            widePad.move(0, 40, 1010);
            compare(wide.contentX, 100, "a vertical delta leaves a horizontal view");
        }

        // 40 px in 100 ms is 400 px a second: times 2.5, over GTK's friction
        // of 4, the view coasts 250 px past the 100 px the deltas moved it.
        function test_a_lift_coasts_the_distance_of_the_last_velocity() {
            tallPad.move(0, 20, 1000);
            tallPad.move(0, 20, 1100);
            compare(tall.contentY, 100);
            tallPad.lift(1100);
            verify(tall.flicking, "the view flicks");
            verify(tall.flickDeceleration !== plain.flickDeceleration, "the view's deceleration is its own");
            tryCompare(tall, "moving", false);
            fuzzyCompare(tall.contentY, 350, 2);
        }

        function test_a_lift_toward_the_start_coasts_that_way() {
            tall.contentY = 1000;
            tallPad.move(0, -20, 1000);
            tallPad.move(0, -20, 1100);
            tallPad.lift(1100);
            tryCompare(tall, "moving", false);
            fuzzyCompare(tall.contentY, 650, 2);
        }

        function test_fingers_that_rested_before_the_lift_do_not_coast() {
            tallPad.move(0, 20, 1000);
            tallPad.move(0, 20, 1100);
            tallPad.lift(1251);
            compare(tall.flicking, false);
            wait(50);
            compare(tall.contentY, 100);
        }

        // The second swipe starts inside the velocity window of the first.
        function test_a_swipe_starts_with_no_delta_or_fraction_of_the_one_before() {
            tallPad.move(0, 20, 1000);
            tallPad.move(0, 21, 1100);
            compare(tall.contentY, 103, "the last delta owes half a pixel");
            tallPad.lift(1100);
            tall.cancelFlick();
            const from = tall.contentY;
            tallPad.move(0, 1, 1120);
            compare(tall.contentY, from + 3, "the half is not paid back after the lift");
            tallPad.lift(1120);
            compare(tall.flicking, false, "one delta after a lift has no velocity");
        }

        function test_a_mouse_wheel_notch_moves_qts_step() {
            mouseWheel(plain, 50, 50, 0, -120);
            mouseWheel(tall, 50, 50, 0, -120);
            tryCompare(plain, "moving", false);
            tryCompare(tall, "moving", false);
            verify(plain.contentY > 0, "the plain view scrolled: " + plain.contentY);
            compare(tall.contentY, plain.contentY);
        }

        function test_the_area_covers_the_part_in_view_under_the_content() {
            tall.contentY = 500;
            compare(tallPad.parent, tall.contentItem);
            compare(listPad.parent, list.contentItem, "a list view's declaration alone leaves it out of the content");
            compare(tallPad.mapToItem(tall, 0, 0), Qt.point(0, 0));
            compare(tallPad.width, tall.width);
            compare(tallPad.height, tall.height);
            verify(tallPad.z < 0, "under every item of the content: " + tallPad.z);
            compare(tallPad.acceptedButtons, Qt.NoButton);
            compare(tallPad.hoverEnabled, false);
        }

        function test_a_view_that_fits_takes_no_swipe() {
            compare(fits.interactive, false);
            compare(root.padOf(fits).enabled, false);
            compare(root.padOf(shrinks).enabled, true);
        }

        // `move` answers what the area's wheel handler accepts, so a delta
        // it does not take reaches the view under the view.
        function test_a_view_takes_no_delta_along_an_axis_it_does_not_scroll_on_data() {
            return [
                { tag: "along a view that scrolls", pad: tallPad, dx: 0, dy: 40, takes: true },
                { tag: "at that view's start", pad: tallPad, dx: 0, dy: -40, takes: true },
                { tag: "across that view", pad: tallPad, dx: 40, dy: 0, takes: false },
                { tag: "along a horizontal view", pad: widePad, dx: 40, dy: 0, takes: true },
                { tag: "across a horizontal view", pad: widePad, dx: 0, dy: 40, takes: false },
                { tag: "mostly across a horizontal view", pad: widePad, dx: 3, dy: 40, takes: false },
                { tag: "along a list that fits", pad: stripPad, dx: 40, dy: 0, takes: false },
                { tag: "across a list that fits", pad: stripPad, dx: 0, dy: 40, takes: false }
            ];
        }
        function test_a_view_takes_no_delta_along_an_axis_it_does_not_scroll_on(row) {
            compare(strip.interactive, true);
            const view = row.pad.view, from = Qt.point(view.contentX, view.contentY);
            compare(row.pad.move(row.dx, row.dy, 1000), row.takes);
            if (!row.takes) compare(Qt.point(view.contentX, view.contentY), from, "a delta left to the view under it moves nothing");
        }

        function test_a_scroll_area_does_not_count_the_area_as_content() {
            compare(shrinks.contentHeight, 300);
            shrinks.contentY = 200;
            root.shrinkHeight = 150;
            compare(shrinks.contentHeight, 150);
        }
    }
}
