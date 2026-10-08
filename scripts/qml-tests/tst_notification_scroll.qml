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
        }
    }

    TestCase {
        name: "notification_scroll"
        when: windowShown

        function test_bottom_fade_data() {
            return [
                { tag: "more below", contentHeight: 300, progress: 0.5, fade: true },
                { tag: "at end", contentHeight: 300, progress: 1, fade: false },
                { tag: "content fits", contentHeight: 50, progress: 0, fade: false }
            ];
        }

        function test_bottom_fade(row) {
            content.Layout.preferredHeight = row.contentHeight;
            tryCompare(frame.flickable, "contentHeight", row.contentHeight + frame.look.stack.tail);
            frame.flickable.contentY = Math.max(0, frame.flickable.contentHeight - frame.flickable.height) * row.progress;
            tryCompare(frame.flickable.layer, "enabled", row.fade);
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
        }
    }
}
