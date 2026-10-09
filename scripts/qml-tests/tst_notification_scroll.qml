import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// The shipped scroll frame fades each edge while more content lies beyond it.
// Both the notification panel and toast stack instantiate this component.
Item {
    id: scene
    width: 600
    height: 300

    Rectangle { anchors.fill: parent; color: "#000000" }

    Notifications.CardScroll {
        id: frame
        look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
        width: implicitWidth
        height: 240
        maxHeight: 240

        Item {
            id: content
            Layout.preferredWidth: 420
            Layout.preferredHeight: 300
            readonly property bool fadeActive: activePointer.containsMouse || activeCard.activeFocus
            readonly property rect fadeArea: Qt.rect(frame.look.stack.pad + activeCard.x,
                activeCard.y - frame.flickable.contentY, activeCard.width, activeCard.height)

            // Paint through the scroll frame's tail as well. Otherwise an
            // end-state grab would sample empty padding instead of proving
            // that painted content keeps its alpha when the mask is off.
            Rectangle {
                width: parent.width
                height: Math.max(parent.height + frame.look.stack.tail, frame.height)
                color: "#ff00ff"
            }

            Rectangle {
                id: activeCard
                x: 80
                width: 120
                height: 40
                color: "#ff00ff"
                activeFocusOnTab: true
                MouseArea {
                    id: activePointer
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
    }

    Notifications.Panel {
        id: panel
        width: implicitWidth
        height: 300
        visible: false
        rows: Array.from({ length: 12 }, (_, index) => ({
            key: "boundary-" + index, app: "Boundary test",
            summary: "Notification " + index, body: "An overflowing shipped panel"
        }))
    }

    Component {
        id: boundaryInk
        Rectangle { color: "#ff00ff"; z: 100 }
    }

    TestCase {
        name: "notification_scroll"
        when: windowShown

        function cleanup() {
            panel.visible = false;
            panel.height = 300;
            frame.visible = true;
            activeCard.focus = false;
            mouseMove(frame, frame.width + 20, 0);
        }

        function test_shipped_panel_boundary_data() {
            return [
                { tag: "top end", progress: 0, height: 300 },
                { tag: "mid scroll", progress: 0.5, height: 300 },
                { tag: "short top end", progress: 0, height: 180 },
                { tag: "short mid scroll", progress: 0.5, height: 180 }
            ];
        }

        function test_shipped_panel_boundary(row) {
            frame.visible = false;
            panel.height = row.height;
            panel.visible = true;
            const scrollbar = findChild(panel, "notificationPanelScrollBar");
            verify(scrollbar !== null);
            const scroll = scrollbar.parent;
            const view = scrollbar.flickable;
            const title = findChild(panel, "notificationHeaderTitleText");
            verify(title !== null);
            const header = title.parent.parent;
            tryVerify(() => view.contentHeight > view.height);
            const headerBottom = header.mapToItem(panel, 0, header.height).y;
            const viewTop = view.mapToItem(panel, 0, 0).y;
            compare(viewTop, headerBottom, "the shipped viewport starts at the actual header bottom");
            compare(view.mapToItem(panel, 0, view.height).y, panel.height,
                "the shipped viewport reaches the panel bottom in its available room");
            compare(scroll.parent.mapToItem(panel, 0, 0).y, headerBottom,
                "the list frame starts at the same boundary");
            verify(view.clip, "the shipped viewport clips its content");
            const masks = Array.from(scroll.children).filter(child => child.gradient !== undefined);
            compare(masks.length, 1, "one alpha gradient owns both list edges");
            const mask = masks[0];
            compare(mask.mapToItem(panel, 0, 0).y, headerBottom,
                "the alpha mask starts at the actual header bottom");
            compare(mask.height, view.height);
            compare(mask.gradient.stops[0].position, 0, "the gradient starts at the clip edge");

            const travel = view.contentHeight - view.height;
            view.contentY = travel * row.progress;
            if (row.progress > 0) verify(view.contentY > 0 && view.contentY < travel);
            // Test ink crosses the shipped clip. It occupies the side gutter,
            // outside the header and active-card mask rectangles. This proves
            // actual clipped and faded paint without relying on card colours.
            const ink = boundaryInk.createObject(view.contentItem, {
                x: 0, y: view.contentY - 16, width: view.width, height: view.height + 32
            });
            verify(ink !== null);
            try {
                panel.Window.window.update();
                verify(waitForRendering(panel));
                const painted = grabImage(scene);
                const x = Math.floor(view.mapToItem(scene, 10, 0).x);
                const edge = Math.floor(view.mapToItem(scene, 0, 0).y);
                for (const distance of [1, 8, 15]) {
                    compare(painted.red(x, edge - distance), 0, "no painted card strip escapes above the header boundary");
                    compare(painted.blue(x, edge - distance), 0);
                }
                if (row.progress === 0) {
                    compare(painted.red(x, edge + 1), 255, "the top end retains full content paint");
                } else {
                    const near = painted.red(x, edge + 1);
                    const middle = painted.red(x, edge + Math.floor(scroll.fadeExtent / 2));
                    const centre = painted.red(x, edge + Math.ceil(scroll.fadeExtent));
                    verify(near < 8 && middle > near && middle < centre,
                        "one smooth painted fade rises from the header boundary");
                    compare(centre, 255);
                    compare(painted.green(x, edge + 1), 0, "the gradient adds no colour");
                    compare(painted.blue(x, edge + 1), near, "the gradient changes alpha only");
                }
            } finally {
                ink.destroy();
            }
        }

        function test_active_card_data() {
            return [
                { tag: "hover top", top: true, keyboard: false },
                { tag: "hover bottom", top: false, keyboard: false },
                { tag: "focus top", top: true, keyboard: true },
                { tag: "focus bottom", top: false, keyboard: true }
            ];
        }

        function test_active_card(row) {
            content.Layout.preferredHeight = 700;
            tryCompare(frame.flickable, "contentHeight", 700 + frame.look.stack.tail);
            frame.flickable.contentY = 200;
            const viewportY = row.top ? 8 : frame.height - activeCard.height - 8;
            activeCard.y = frame.flickable.contentY + viewportY;
            mouseMove(frame, frame.width + 20, 0);
            if (row.keyboard) activeCard.forceActiveFocus(Qt.TabFocusReason);
            else mouseMove(activeCard, activeCard.width / 2, activeCard.height / 2);
            tryCompare(content, "fadeActive", true);
            compare(content.fadeArea, Qt.rect(frame.look.stack.pad + activeCard.x,
                viewportY, activeCard.width, activeCard.height));
            frame.Window.window.update();
            verify(waitForRendering(frame));
            const image = grabImage(frame);
            const x = Math.floor(frame.look.stack.pad + activeCard.x + activeCard.width / 2);
            for (const inset of [2, activeCard.height / 2, activeCard.height - 3]) {
                const y = Math.floor(viewportY + inset);
                compare(image.red(x, y), 255, "the active card keeps its full paint inside the fade");
                compare(image.green(x, y), 0, "the exemption adds no colour");
                compare(image.blue(x, y), 255, "the exemption changes alpha only");
                verify(image.red(frame.look.stack.pad + 20, y) < 230,
                    "other content at the same edge keeps its smooth fade");
            }
            cleanup();
            tryCompare(content, "fadeActive", false);
            frame.Window.window.update();
            verify(waitForRendering(frame));
            const released = grabImage(frame);
            verify(released.red(x, Math.floor(viewportY + activeCard.height / 2)) < 230,
                "the card returns to the fade after pointer and focus leave");
        }

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
            verify(frame.look.stack.fadeHeight > 60, "the fade extends beyond the old cutoff");
            content.Layout.preferredHeight = row.contentHeight;
            tryCompare(frame.flickable, "contentHeight", row.contentHeight + frame.look.stack.tail);
            frame.flickable.contentY = Math.max(0, frame.flickable.contentHeight - frame.flickable.height) * row.progress;
            tryCompare(frame.flickable.layer, "enabled", row.top || row.bottom);
            checkPaint(row.top, row.bottom);
        }

        function test_endpoint_continuity_data() {
            // Qt MultiEffect applies smoothstep to the mask alpha. Cubic
            // distance easing gives 0.84375, 0.5 and 0.15625 mask alpha at
            // quarter, half and three-quarter distances. The second
            // smoothstep paints approximately 238, 128 and 17 over black.
            // These bounds allow the edge pixel footprint but exclude
            // both an opaque edge and an immediate full fade.
            const distances = [
                { fraction: 0, minimum: 255, maximum: 255 },
                { fraction: 0.001, minimum: 254, maximum: 255 },
                { fraction: 0.25, minimum: 232, maximum: 246 },
                { fraction: 0.5, minimum: 125, maximum: 138 },
                { fraction: 0.75, minimum: 10, maximum: 28 },
                { fraction: 1, minimum: 0, maximum: 8 }
            ];
            const rows = [];
            for (const top of [true, false]) {
                for (const distance of distances) {
                    rows.push({
                        tag: (top ? "top " : "bottom ") + distance.fraction,
                        top: top, fraction: distance.fraction,
                        minimum: distance.minimum, maximum: distance.maximum
                    });
                }
            }
            return rows;
        }

        function test_endpoint_continuity(row) {
            content.Layout.preferredHeight = 700;
            tryCompare(frame.flickable, "contentHeight", 700 + frame.look.stack.tail);
            const travel = frame.flickable.contentHeight - frame.flickable.height;
            const distance = frame.look.stack.fadeHeight * row.fraction;
            frame.flickable.contentY = row.top ? distance : travel - distance;
            frame.Window.window.update();
            verify(waitForRendering(frame));
            const painted = grabImage(frame);
            const x = Math.floor(painted.width / 2);
            const y = row.top ? 1 : painted.height - 2;
            const ink = painted.red(x, y);
            verify(ink >= row.minimum && ink <= row.maximum,
                   "the painted edge approaches its endpoint continuously: " + ink);
            compare(painted.green(x, y), 0, "the mask adds no surface colour");
            compare(painted.blue(x, y), ink, "the mask changes alpha only");
            compare(painted.red(x, Math.floor(painted.height / 2)), 255, "the card centre keeps its ink");
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
                    verify(middle >= 95 && middle <= 160, "the symmetric easing keeps the middle of the band soft");
                    const beyondOldBand = at(edge.top ? 72 : frame.height - 72);
                    verify(painted.red(x, beyondOldBand) < 255, "the painted fade extends beyond the old band");
                } else {
                    compare(middle, 255, "the band stays opaque at its own end");
                    compare(near, 255, "the edge stays opaque at its own end");
                }
            }
        }

        function test_hiding_releases_the_layers() {
            content.Layout.preferredHeight = 700;
            tryCompare(frame.flickable, "contentHeight", 700 + frame.look.stack.tail);
            frame.flickable.contentY = 150;
            tryCompare(frame.flickable.layer, "enabled", true);
            frame.visible = false;
            compare(frame.flickable.layer.enabled, false);
            frame.visible = true;
            tryCompare(frame.flickable.layer, "enabled", true);
            checkPaint(true, true);
        }
    }
}
