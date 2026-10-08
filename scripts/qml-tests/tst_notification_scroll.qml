import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// The shipped scroll frame fades each edge while more content lies beyond it.
// Both the notification panel and toast stack instantiate this component.
Item {
    width: 600
    height: 300

    Rectangle { anchors.fill: parent; color: "#000000" }

    Notifications.CardScroll {
        id: frame
        look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
        width: implicitWidth
        height: 180
        maxHeight: 180

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

        function test_edge_fades_data() {
            return [
                { tag: "both edges", contentHeight: 500, progress: 0.5, top: true, bottom: true },
                { tag: "at top", contentHeight: 500, progress: 0, top: false, bottom: true },
                { tag: "at bottom", contentHeight: 500, progress: 1, top: true, bottom: false },
                { tag: "content fits", contentHeight: 50, progress: 0, top: false, bottom: false },
                { tag: "overflow again", contentHeight: 500, progress: 0.5, top: true, bottom: true }
            ];
        }

        function test_edge_fades(row) {
            compare(frame.look.stack.tail, 24, "the scroll tail keeps its original size");
            compare(frame.look.stack.fadeHeight, 60, "both edges use the named fade size");
            content.Layout.preferredHeight = row.contentHeight;
            tryCompare(frame.flickable, "contentHeight", row.contentHeight + frame.look.stack.tail);
            frame.flickable.contentY = Math.max(0, frame.flickable.contentHeight - frame.flickable.height) * row.progress;
            tryCompare(frame.flickable.layer, "enabled", row.top || row.bottom);
            checkPaint(row.top, row.bottom);
        }

        function checkPaint(topFade, bottomFade) {
            compare(frame.GraphicsInfo.shaderType, GraphicsInfo.RhiShader, "the mask uses a shader-capable renderer");
            frame.Window.window.update();
            verify(waitForRendering(frame));
            // QtTest grabs opaque window RGB. Magenta over black measures
            // composited content alpha independently of the window alpha.
            const painted = grabImage(frame);
            const x = Math.floor(painted.width / 2);
            const at = y => Math.floor(y * painted.height / frame.height);
            const centre = painted.red(x, at(frame.height / 2));
            compare(centre, 255, "paint between the fade bands stays opaque");
            for (const edge of [{ top: true, fade: topFade }, { top: false, fade: bottomFade }]) {
                const nearY = edge.top ? 1 : painted.height - 2;
                const middleY = at(edge.top ? frame.look.stack.fadeHeight / 2 : frame.height - frame.look.stack.fadeHeight / 2);
                const near = painted.red(x, nearY);
                const middle = painted.red(x, middleY);
                compare(painted.green(x, nearY), 0, "the mask adds no colour band");
                compare(painted.blue(x, nearY), near, "the mask changes paint alpha only");
                if (edge.fade) {
                    verify(near < 64, "content fades at the overflowing edge");
                    verify(middle > near && middle < centre, "alpha rises toward the opaque centre");
                } else {
                    compare(middle, 255, "the band stays opaque at its own end");
                    compare(near, 255, "the edge stays opaque at its own end");
                }
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
            checkPaint(true, true);
        }
    }
}
