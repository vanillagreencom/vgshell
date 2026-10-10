import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// The shipped scroll frame fades each edge while more content lies beyond it.
// Both the notification panel and toast stack instantiate this component.
// In the panel the list's view starts at the header's bottom edge and its
// first card below the gutter under the header; the top edge fades across
// the same band as the bottom, with no strength while the view rests at its
// start; nothing lifts the fade from a hovered or keyboard-selected card, a
// pointer crossing the gap between two cards moves the hover from one to
// the other once, and a keyboard move reveals the selected card clear of
// both bands.
Item {
    id: scene
    width: 600
    // Room for the tallest shipped panel a test opens.
    height: 640

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
            mouseMove(scene, scene.width - 1, scene.height - 1);
            if (panel.visible) {
                panel.selectIndex(0);
                panelParts().view.contentY = 0;
            }
            panel.visible = false;
            panel.height = 300;
            frame.visible = true;
        }

        function descendants(item) {
            const found = [];
            for (const child of item.children) found.push(child, ...descendants(child));
            return found;
        }

        // The shipped panel's parts, read through the names it ships and
        // its structure: the scroll frame, its view, the header and the
        // card faces with the slots that hold them, in list order. The
        // gutter is the header's inset, the divider and the focus ring's
        // room, read from the tokens, independent of the Pane's own sum.
        function panelParts() {
            const scrollbar = findChild(panel, "notificationPanelScrollBar");
            verify(scrollbar !== null);
            const title = findChild(panel, "notificationHeaderTitleText");
            verify(title !== null);
            const header = title.parent.parent;
            const view = scrollbar.flickable;
            const faces = descendants(view.contentItem).filter(child => child.reportHover !== undefined && child.card !== undefined);
            const headerInset = header.mapToItem(panel, 0, 0).y;
            return {
                scroll: scrollbar.parent, view: view, header: header, faces: faces,
                headerBottom: header.mapToItem(panel, 0, header.height).y,
                gutter: headerInset + Theme.divider.thickness + Theme.focusRing.width + Theme.focusRing.offset
            };
        }

        function showPanel(height) {
            frame.visible = false;
            panel.height = height;
            panel.visible = true;
            const parts = panelParts();
            tryVerify(() => parts.view.contentHeight > parts.view.height && parts.faces.length === panel.rows.length);
            return parts;
        }

        function grabPanel() {
            panel.Window.window.update();
            verify(waitForRendering(panel));
            return grabImage(scene);
        }

        // Test ink over a slot, which a card's lift does not move, so the
        // same pixels read the mask alone whatever the card draws.
        function inkOver(slot) {
            const ink = boundaryInk.createObject(slot, { x: 0, y: 0, width: slot.width, height: slot.height });
            verify(ink !== null);
            return ink;
        }

        function test_shipped_panel_boundary_data() {
            return [
                { tag: "top end", progress: 0, height: 300 },
                { tag: "mid scroll", progress: 0.5, height: 300 },
                { tag: "short top end", progress: 0, height: 180 },
                { tag: "short mid scroll", progress: 0.5, height: 180 },
                // The top band grows in as the view leaves its start, so
                // a card that has just started under the header has
                // barely begun to fade.
                { tag: "just left the top", offset: 12, height: 300, growing: true }
            ];
        }

        function test_shipped_panel_boundary(row) {
            const parts = showPanel(row.height);
            const view = parts.view;
            const scroll = parts.scroll;
            const viewTop = view.mapToItem(panel, 0, 0).y;
            compare(viewTop, parts.headerBottom, "the shipped viewport starts at the header's bottom edge");
            compare(view.mapToItem(panel, 0, view.height).y, panel.height,
                "the shipped viewport reaches the panel bottom in its available room");
            compare(scroll.parent.mapToItem(panel, 0, 0).y, parts.headerBottom,
                "the list frame starts at the same edge");
            verify(view.clip, "the shipped viewport clips its content");
            const masks = Array.from(scroll.children).filter(child => child.gradient !== undefined);
            compare(masks.length, 1, "one alpha gradient owns both list edges");
            const mask = masks[0];
            compare(mask.mapToItem(panel, 0, 0).y, parts.headerBottom,
                "the alpha mask starts at the header's bottom edge");
            compare(mask.height, view.height);
            compare(mask.gradient.stops[0].position, 0, "the gradient starts at the clip edge");

            const travel = view.contentHeight - view.height;
            view.contentY = row.offset !== undefined ? row.offset : travel * row.progress;
            const rest = view.contentY === 0;
            if (!rest) verify(view.contentY > 0 && view.contentY < travel);
            if (rest) fuzzyCompare(parts.faces[0].parent.mapToItem(panel, 0, 0).y, parts.headerBottom + parts.gutter, 0.5,
                "at rest the first card's slot starts where the gutter ends");
            // Test ink crosses the shipped clip in the side room, beside
            // the cards and the header. This proves actual clipped and
            // faded paint without relying on card colours.
            const ink = boundaryInk.createObject(view.contentItem, {
                x: 0, y: view.contentY - 16, width: view.width, height: view.height + 32
            });
            verify(ink !== null);
            try {
                const painted = grabPanel();
                const x = Math.floor(view.mapToItem(scene, 10, 0).x);
                const edge = Math.floor(view.mapToItem(scene, 0, 0).y);
                const band = Math.ceil(scroll.fadeExtent);
                for (const distance of [1, 8, 15]) {
                    compare(painted.red(x, edge - distance), 0, "no painted card strip escapes above the header's bottom edge");
                    compare(painted.blue(x, edge - distance), 0);
                }
                if (rest) {
                    // The top band has no strength at the view's start:
                    // the gutter and the first card paint in full, down
                    // to the bottom band.
                    for (let y = edge + 1; y < edge + view.height - band; y += 2)
                        compare(painted.red(x, y), 255, "at rest the top of the list paints in full at " + (y - edge));
                } else {
                    const near = painted.red(x, edge + 1);
                    const pastGutter = painted.red(x, edge + Math.ceil(parts.gutter) + 2);
                    const middle = painted.red(x, edge + Math.floor(band / 2));
                    const centre = painted.red(x, edge + band);
                    compare(centre, 255, "content below the top band paints in full");
                    if (row.growing) {
                        verify(near >= 240 && near < 255, "the top band has begun to grow in, short of its strength: " + near);
                    } else {
                        verify(view.contentY >= band, "the view has left its start by the band's height");
                        verify(near < 8 && middle > near && middle < centre,
                            "one smooth painted fade rises across the top band: " + [near, middle, centre]);
                        verify(pastGutter < 64, "the fade reaches past the gutter: " + pastGutter);
                    }
                    let previous = near;
                    for (let y = edge + 1; y <= edge + band; y++) {
                        verify(painted.red(x, y) >= previous - 1, "the fade rises without a step back at " + (y - edge));
                        previous = painted.red(x, y);
                    }
                    compare(painted.green(x, edge + 1), 0, "the gradient adds no colour");
                    compare(painted.blue(x, edge + 1), near, "the gradient changes alpha only");
                }
            } finally {
                ink.destroy();
            }
        }

        function test_active_card_keeps_the_fade_data() {
            return [
                { tag: "hover top", top: true, keyboard: false },
                { tag: "hover bottom", top: false, keyboard: false },
                { tag: "focus top", top: true, keyboard: true },
                { tag: "focus bottom", top: false, keyboard: true }
            ];
        }

        // A hovered card, and the selected card while the list holds the
        // keyboard, paint the same pixels inside a fade band as they do
        // without the pointer or the keyboard: the band's alpha is kept.
        function test_active_card_keeps_the_fade(row) {
            const parts = showPanel(400);
            const view = parts.view;
            const face = parts.faces[6];
            const slot = face.parent;
            const list = slot.parent;
            if (row.keyboard) panel.selectIndex(6);
            // Place the card's face in the band: its top just under the
            // header's edge, or its bottom just above the view's bottom.
            const faceTop = row.top ? 2 : view.height - face.height - 2;
            view.contentY = face.mapToItem(view.contentItem, 0, 0).y - faceTop;
            const band = parts.scroll.fadeExtent;
            verify(view.contentY > 0 && view.contentY < view.contentHeight - view.height);
            const ink = inkOver(slot);
            try {
                const x = Math.floor(slot.mapToItem(scene, slot.width / 2, 0).x);
                const edge = Math.floor(view.mapToItem(scene, 0, 0).y);
                // The rows of the band the slot's ink covers, in the view.
                const slotTop = slot.mapToItem(view, 0, 0).y;
                const first = Math.ceil(Math.max(row.top ? 0 : view.height - band, slotTop)) + 1;
                const last = Math.floor(Math.min(row.top ? band : view.height, slotTop + slot.height)) - 1;
                const rows = [];
                for (let y = first; y < last; y += 2) rows.push(edge + y);
                verify(rows.length > 2, "the slot crosses the band");
                const rest = grabPanel();
                if (row.keyboard) {
                    list.forceActiveFocus(Qt.TabFocusReason);
                    tryCompare(list, "activeFocus", true);
                } else {
                    mouseMove(slot, slot.width / 2, row.top ? slot.height - 4 : 4);
                    tryCompare(face, "hovered", true);
                }
                const active = grabPanel();
                let faded = 0;
                for (const y of rows) {
                    verify(Math.abs(active.red(x, y) - rest.red(x, y)) <= 1,
                        "the active card keeps the fade's alpha at " + y + ": " + [rest.red(x, y), active.red(x, y)]);
                    compare(active.green(x, y), 0, "the band adds no colour");
                    if (rest.red(x, y) < 230) faded += 1;
                }
                verify(faded > 0, "the sampled card lies in the band's fade");
            } finally {
                ink.destroy();
                list.focus = false;
            }
        }

        // Scrolled past the band's height, a card whose middle lies halfway
        // through the top band paints half faded, dimmer than a card between
        // the bands, and that band is taller than the gutter.
        function test_scrolled_card_fades_in_the_top_band() {
            const parts = showPanel(440);
            const view = parts.view;
            const band = parts.scroll.fadeExtent;
            verify(band > 2 * parts.gutter, "the band is taller than the gutter: " + [band, parts.gutter]);
            const faded = parts.faces[5];
            view.contentY = faded.mapToItem(view.contentItem, 0, faded.height / 2).y - band / 2;
            verify(view.contentY >= band && view.contentY < view.contentHeight - view.height);
            const clear = parts.faces.find(face => {
                const top = face.parent.mapToItem(view, 0, 0).y;
                return top >= band && top + face.parent.height <= view.height - band;
            });
            verify(clear !== undefined, "a card stands between the bands");
            const inks = [inkOver(faded.parent), inkOver(clear.parent)];
            try {
                const painted = grabPanel();
                const x = Math.floor(faded.parent.mapToItem(scene, faded.parent.width / 2, 0).x);
                const middle = face => painted.red(x, Math.floor(face.mapToItem(scene, 0, face.height / 2).y));
                compare(middle(clear), 255, "a card between the bands paints in full");
                verify(middle(faded) >= 95 && middle(faded) <= 160,
                    "a card halfway through the top band is half faded: " + middle(faded));
            } finally {
                inks.forEach(ink => ink.destroy());
            }
        }

        // A pointer swept in 1 px steps from the middle of one card down
        // across the gap into the next: the hover passes from the first
        // card to the second once, and no step reads neither or both.
        function test_pointer_crosses_the_gap_once() {
            const parts = showPanel(600);
            const upper = parts.faces[1];
            const lower = parts.faces[2];
            const x = upper.parent.mapToItem(panel, upper.parent.width / 2, 0).x;
            const from = Math.round(upper.mapToItem(panel, 0, upper.height / 2).y);
            const to = Math.round(lower.mapToItem(panel, 0, lower.height / 2).y);
            verify(lower.mapToItem(panel, 0, lower.height).y < panel.height - parts.scroll.fadeExtent,
                "both cards sit inside the view");
            const sweep = read => {
                const states = [];
                for (let y = from; y <= to; y++) {
                    mouseMove(panel, x, y);
                    const state = (read(upper) ? "upper" : "") + (read(lower) ? "lower" : "");
                    if (states.length === 0 || states[states.length - 1].state !== state) states.push({ state: state, y: y });
                }
                mouseMove(scene, scene.width - 1, scene.height - 1);
                tryVerify(() => !read(upper) && !read(lower));
                return states;
            };
            const shipped = sweep(face => face.hovered);
            compare(shipped.map(step => step.state), ["upper", "lower"],
                "the hover changes once across the gap: " + JSON.stringify(shipped));
            // Control: the cards' own hover, the source before the slots
            // carried it, sees the gap between the faces as neither card.
            const own = sweep(face => face.card.hovered);
            verify(own.some(step => step.state === "") || own.length > 2,
                "the cards' own hover shows the gap the sweep must cross: " + JSON.stringify(own));
        }

        function test_keyboard_reveal_clears_the_bands() {
            const parts = showPanel(480);
            const view = parts.view;
            const list = parts.faces[0].parent.parent;
            verify(parts.faces.every(face => face.parent.height <= view.height - 2 * parts.scroll.fadeExtent),
                "every card fits between the bands");
            list.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(list, "activeFocus", true);
            const check = (index, key) => {
                compare(panel.currentIndex, index);
                const slot = parts.faces[index].parent;
                const top = slot.mapToItem(view.contentItem, 0, 0).y;
                const travel = view.contentHeight - view.height;
                verify(top >= view.contentY + parts.scroll.fadeExtent - 0.5 || view.contentY <= 0,
                    key + " " + index + " leaves the card in the top band: " + [top, view.contentY]);
                verify(top + slot.height <= view.contentY + view.height - parts.scroll.fadeExtent + 0.5 || view.contentY >= travel - 0.5,
                    key + " " + index + " leaves the card in the bottom band: " + [top + slot.height, view.contentY]);
                const ink = inkOver(slot);
                try {
                    const painted = grabPanel();
                    const face = parts.faces[index];
                    const x = Math.floor(slot.mapToItem(scene, slot.width / 2, 0).x);
                    const faceTop = Math.ceil(face.mapToItem(scene, 0, 0).y) + 1;
                    for (let y = faceTop; y < faceTop + face.height - 2; y += 3)
                        compare(painted.red(x, y), 255, key + " " + index + " paints the selected card in full at " + y);
                } finally {
                    ink.destroy();
                }
            };
            for (let index = 1; index < panel.rows.length; index++) {
                keyClick(Qt.Key_Down);
                check(index, "Down");
            }
            for (let index = panel.rows.length - 2; index >= 0; index--) {
                keyClick(Qt.Key_Up);
                check(index, "Up");
            }
            list.focus = false;
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
