import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// The shipped scroll frame fades only unread content below its viewport.
// Both the notification panel and toast stack instantiate this component.
Item {
    width: 600
    height: 300

    Rectangle { anchors.fill: parent; color: "#000000" }

    Notifications.CardScroll {
        id: frame
        look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
        width: implicitWidth
        height: 100
        maxHeight: 100

        Item {
            id: content
            Layout.preferredWidth: 420
            Layout.preferredHeight: 300

            // Paint through the scroll frame's tail as well. Otherwise an
            // end-state grab would sample empty padding instead of proving
            // that painted content keeps its alpha when the mask is off.
            Rectangle {
                width: parent.width
                height: Math.max(parent.height + frame.look.stack.tail, frame.height)
                color: "#ff00ff"
            }
        }
    }

    TestCase {
        name: "notification_scroll"
        when: windowShown

        function test_bottom_fade_data() {
            return [
                { tag: "more below", contentHeight: 300, progress: 0.5, fade: true },
                { tag: "at end", contentHeight: 300, progress: 1, fade: false },
                { tag: "content fits", contentHeight: 50, progress: 0, fade: false },
                { tag: "more below again", contentHeight: 300, progress: 0.5, fade: true }
            ];
        }

        function test_bottom_fade(row) {
            content.Layout.preferredHeight = row.contentHeight;
            tryCompare(frame.flickable, "contentHeight", row.contentHeight + frame.look.stack.tail);
            frame.flickable.contentY = Math.max(0, frame.flickable.contentHeight - frame.flickable.height) * row.progress;
            tryCompare(frame.flickable.layer, "enabled", row.fade);
            checkPaint(row.fade);
        }

        function checkPaint(fade) {
            compare(frame.GraphicsInfo.shaderType, GraphicsInfo.RhiShader, "the mask uses a shader-capable renderer");
            frame.Window.window.update();
            verify(waitForRendering(frame));
            // QtTest grabImage crops the rendered window, whose alpha is
            // opaque. Magenta paint over black measures the content alpha
            // through its composited red and blue channels instead.
            const painted = grabImage(frame);
            const x = Math.floor(painted.width / 2);
            const at = y => Math.floor(y * painted.height / frame.height);
            const above = painted.red(x, at(frame.height - frame.look.stack.tail - 2));
            const middle = painted.red(x, at(frame.height - frame.look.stack.tail / 2));
            const bottom = painted.red(x, painted.height - 2);
            compare(painted.green(x, painted.height - 2), 0, "the mask adds no colour band");
            compare(painted.blue(x, painted.height - 2), bottom, "the mask changes paint alpha only");
            compare(above, 255, "content above the fade stays opaque");
            if (fade) {
                verify(bottom < 64, "the bottom content fades to transparent");
                verify(middle > bottom && middle < above, "alpha decreases within the fade band");
            } else {
                compare(middle, 255, "unmasked content stays opaque within the band");
                compare(bottom, 255, "unmasked bottom content stays opaque");
            }
        }

        function test_hiding_releases_the_layers() {
            content.Layout.preferredHeight = 300;
            tryCompare(frame.flickable, "contentHeight", 300 + frame.look.stack.tail);
            frame.flickable.contentY = 100;
            tryCompare(frame.flickable.layer, "enabled", true);
            frame.visible = false;
            compare(frame.flickable.layer.enabled, false);
            frame.visible = true;
            tryCompare(frame.flickable.layer, "enabled", true);
            checkPaint(true);
        }
    }
}
