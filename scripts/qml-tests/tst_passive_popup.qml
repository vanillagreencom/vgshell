import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// PassivePopup: a surface under the item it is declared in that takes no
// keyboard. It opens and closes with the flyout motion, at once at motion
// scale 0, keeps its content mapped while it closes, closes at once when its
// anchor hides, and publishes the box it takes in its anchor's window: under
// the anchor, its right edge at the anchor's right edge, slid to stay in the
// window, and empty once closed. Expected values are worked by hand from
// the defaults in Tokens.js: a 4 px popover gap. The stand-in PopupWindow
// positions nothing; the nested sandbox proves placement on screen.
Item {
    id: root
    width: 400
    height: 300

    Item {
        id: anchor
        x: 300
        y: 10
        width: 24
        height: 24
        PassivePopup {
            id: popup
            width: 200
            Rectangle { objectName: "popupContent"; width: parent.width; height: 50 }
        }
    }

    function windowOf() {
        return Array.from(popup.data).find(child => child instanceof Window);
    }

    UnitCase {
        name: "passivePopup"
        when: windowShown

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            anchor.visible = true;
            anchor.x = 300;
            popup.shown = false;
            UnitTheme.reset();
        }

        function test_it_opens_and_closes_with_the_flyout_motion() {
            popup.shown = true;
            compare(windowOf().visible, true, "the popup maps as it shows");
            verify(popup.motionProgress < 1, "the popup moves in, not at once: " + popup.motionProgress);
            tryCompare(popup, "motionProgress", 1, 2000);
            popup.shown = false;
            compare(windowOf().visible, true, "the popup stays mapped while it moves out");
            compare(popup.drawing, true);
            tryCompare(popup, "motionProgress", 0, 2000);
            tryCompare(windowOf(), "visible", false);
            compare(popup.drawing, false);
        }

        function test_motion_scale_zero_opens_and_closes_at_once() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            popup.shown = true;
            compare(popup.motionProgress, 1, "the popup shows whole at once");
            popup.shown = false;
            compare(popup.motionProgress, 0, "the popup goes at once");
            compare(windowOf().visible, false);
        }

        function test_it_takes_no_keyboard() {
            compare(windowOf().grabFocus, false);
        }

        function test_its_placed_box_sits_under_the_anchor_inside_its_window() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            popup.shown = true;
            compare([popup.placedBox.x, popup.placedBox.y, popup.placedBox.width, popup.placedBox.height],
                [324 - 200, 10 + 24 + 4, 200, 50], "its right edge at the anchor's right edge");
            anchor.x = 20;
            tryVerify(() => popup.placedBox.x === 0, 1000, "slid in at the window's left edge");
            anchor.x = 390;
            tryVerify(() => popup.placedBox.x === 400 - 200, 1000, "slid in at the window's right edge");
            popup.shown = false;
            compare([popup.placedBox.width, popup.placedBox.height], [0, 0], "a closed popup takes no box");
        }

        function test_a_hidden_anchor_closes_it_at_once() {
            popup.shown = true;
            tryCompare(popup, "motionProgress", 1, 2000);
            anchor.visible = false;
            compare(windowOf().visible, false, "the popup leaves with its anchor");
            compare(popup.motionProgress, 0);
            compare([popup.placedBox.width, popup.placedBox.height], [0, 0]);
        }
    }
}
