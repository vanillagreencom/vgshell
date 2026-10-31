import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Unit
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// The shipped scroll frame fades each edge while more content lies beyond it.
// Both the notification panel and toast stack instantiate this component.
// In the panel the list's view starts at the header's bottom edge, its
// first card stands the card gap under the header and each card the card
// gap above the next, the selected one included; the top edge fades across
// the look's header band, which has no strength while the view rests at its
// start and its whole strength once the first card meets the header, so
// every card crosses the same band; nothing lifts the fade from a hovered or keyboard-selected card, a
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

    readonly property var notificationRows: Array.from({ length: 12 }, (_, index) => ({
        key: "boundary-" + index, app: "Boundary test",
        summary: "Notification " + index, body: "An overflowing shipped panel"
    }))

    Notifications.Panel {
        id: panel
        width: implicitWidth
        height: 300
        visible: false
        // Drive the shipped open/refresh lifecycle through its snapshot
        // interface. The service owns data; this unit test owns its input.
        shell: ({ status: { revision: 0 }, settings: {}, ipc: { call: (name, arg) =>
            name === "panel-state" ? JSON.stringify({ mode: "inbox", rows: scene.notificationRows }) : "ok" } })
    }

    Component {
        id: boundaryInk
        Rectangle { color: "#ff00ff"; z: 100 }
    }

    Component { id: shippedMeasure; Notifications.RowMeasure { measureOnly: true } }
    Component { id: measuredCard; Notifications.NotificationCard {} }
    Component { id: measureParent; Item {} }

    // Synthetic screenshot-sized PNG. The hidden decoder, not a file-size
    // or source-text check, must retain only the painted token's pixels.
    readonly property string screenshotImage: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAACgAAAAWgAQAAAAC6eydyAAAB10lEQVR4nO3BMQEAAADCoPVPbQ0PoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIDODQ4JAAEjBuWbAAAAAElFTkSuQmCC"

    UnitCase {
        id: testCase
        name: "notification_scroll"
        when: windowShown

        function cleanup() {
            mouseMove(scene, scene.width - 1, scene.height - 1);
            if (panel.visible) {
                panel.selectIndex(0);
                panelParts().view.contentY = 0;
            }
            panel.close();
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
        // gutter is the look's card gap.
        function panelParts() {
            const scrollbar = findChild(panel, "notificationPanelScrollBar");
            verify(scrollbar !== null);
            const title = findChild(panel, "notificationHeaderTitleText");
            verify(title !== null);
            const header = title.parent.parent;
            const view = scrollbar.flickable;
            const slots = descendants(view.contentItem).filter(child => child.extent !== undefined && child.entry !== undefined);
            const cardFaces = () => descendants(view.contentItem).filter(child => child.reportHover !== undefined && child.card !== undefined);
            return {
                scroll: scrollbar.parent, view: view, header: header, slots: slots,
                get faces() { return cardFaces(); },
                faceAt: index => cardFaces().find(face => face.key === panel.rows[index].key),
                slotOf: face => slots.find(slot => slot.entry.key === face.key),
                headerBottom: header.mapToItem(panel, 0, header.height).y,
                gutter: panel.look.card.gap
            };
        }

        property bool openSettled: false
        function showPanel(height) {
            frame.visible = false;
            panel.height = height;
            panel.visible = true;
            openSettled = false;
            panel.open("{}");
            // This callback follows open's queued selectIndex callback.
            // Confirm the initial production selection before user input.
            Qt.callLater(() => openSettled = true);
            tryCompare(testCase, "openSettled", true);
            compare(panel.currentIndex, 0);
            compare(panel.selectedKey, scene.notificationRows[0].key);
            const parts = panelParts();
            tryVerify(() => parts.view.contentHeight > parts.view.height && parts.slots.length === panel.rows.length);
            waitViewport(parts);
            verify(parts.faces.length < panel.rows.length, "offscreen rows keep slots without constructing cards");
            return parts;
        }

        function waitViewport(parts) {
            tryVerify(() => {
                const visible = parts.slots.filter(slot => {
                    const y = slot.mapToItem(parts.view, 0, 0).y;
                    return y < parts.view.height && y + slot.height - panel.look.card.gap > 0;
                });
                return visible.length > 0 && visible.every(slot => {
                    const face = parts.faceAt(slot.index);
                    return face !== undefined && face.width > 0 && face.height > 0
                        && Math.abs(face.height + panel.look.card.gap - slot.height) < 0.5;
                });
            });
        }

        function bringRowIntoView(parts, index) {
            const slot = parts.slots[index];
            const top = slot.mapToItem(parts.view.contentItem, 0, 0).y;
            parts.view.contentY = Math.max(0, Math.min(top - parts.scroll.fadeExtent,
                parts.view.contentHeight - parts.view.height));
            waitViewport(parts);
            const face = parts.faceAt(index);
            verify(face !== undefined, "scrolling builds the actual offscreen card");
            return face;
        }

        function grabPanel() {
            panel.Window.window.update();
            verify(renderedFrame(panel));
            return grabImage(scene);
        }

        // Test ink over a slot, which a card's lift does not move, so the
        // same pixels read the mask alone whatever the card draws.
        function inkOver(slot) {
            const ink = boundaryInk.createObject(slot, { x: 0, y: 0, width: slot.width, height: slot.height });
            verify(ink !== null);
            return ink;
        }

        function measureCard(look) {
            return { look: look, pad: look.card.pad, summary: "", title: "", singleLine: true,
                showsBadge: false, enrichment: null, workspace: "", workspaceIcon: "", bodySegments: [] };
        }

        function alteredMeasure(look, bound, replacement) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.notifications/RowMeasure.qml"), false);
            request.send();
            const source = request.responseText;
            compare(source.split(bound).length, 2, "the planted measurement mutation matches once");
            const planted = source.replace(bound, replacement);
            verify(planted !== source);
            const at = planted.indexOf("ColumnLayout {");
            verify(at > 0);
            const wrapper = planted.slice(0, at) + "Item { component AlteredMeasure: " + planted.slice(at)
                + "\n readonly property Component measure: Component { AlteredMeasure {} } }";
            const owner = Qt.createQmlObject(wrapper, scene, Qt.resolvedUrl("../../shell/plugins/vgs.notifications/ControlMeasure.qml"));
            verify(owner !== null);
            const measure = owner.measure.createObject(owner, { measureOnly: true, rowCard: measureCard(look) });
            verify(measure !== null);
            return { owner: owner, measure: measure };
        }

        function test_hidden_and_visible_card_measurement_data() {
            const wrapped = "Wrapped summary with enough words to cross the text width and continue on the second line";
            const body = "Wrapped body text with enough words to occupy more than one full line in the notification card.";
            return [
                { tag: "visible wrapped summary", summary: wrapped, body: body, shown: true },
                { tag: "hidden wrapped summary", summary: wrapped, body: body, shown: false },
                { tag: "hidden long body", summary: "Long body", body: body.repeat(8), shown: false },
                { tag: "hidden body only", summary: "", body: body, shown: false },
                { tag: "visibility-dependent font control", summary: wrapped, body: body, shown: false, control: true }
            ];
        }

        function test_hidden_and_visible_card_measurement(row) {
            const look = frame.look;
            const parent = createTemporaryObject(measureParent, scene, { visible: row.shown });
            verify(parent !== null);
            const altered = row.control ? alteredMeasure(look,
                "rowCard.summary.length > 0 ? rowCard.look.text.title.size : rowCard.look.text.body.size",
                "summaryRow.visible ? rowCard.look.text.title.size : rowCard.look.text.body.size") : null;
            const measure = altered !== null ? altered.measure
                : shippedMeasure.createObject(parent, { rowCard: measureCard(look) });
            verify(measure !== null);
            if (altered !== null) altered.owner.visible = row.shown;
            const entry = { app: "Measurement test", summary: row.summary, body: row.body };
            const card = createTemporaryObject(measuredCard, scene, {
                look: look, textColumn: frame.textColumn, app: entry.app, summary: entry.summary, body: entry.body
            });
            verify(card !== null);
            try {
                card.settleHeight();
                const predicted = measure.measure(entry, look, card.textColumn);
                const title = findChild(measure, "notificationTitleText");
                verify(title !== null);
                compare(title.visible, row.shown && row.summary.length > 0);
                if (row.control) expectFail("", "the hidden font must not depend on inherited visibility");
                compare(title.font.pixelSize, row.summary.length > 0 ? look.text.title.size : look.text.body.size);
                if (row.control) return;
                compare(title.font.weight, row.summary.length > 0 ? look.text.title.weight : Font.Normal);
                fuzzyCompare(predicted, card.fullHeight, 0.5,
                    "the same content has the same measured and visible card height");
            } finally {
                if (altered !== null) altered.owner.destroy();
                else measure.destroy();
            }
        }

        function test_hidden_decoder_data() {
            return [
                { tag: "screenshot", badge: false },
                { tag: "workspace badge", badge: true },
                { tag: "unbounded screenshot control", badge: false, control: true },
                { tag: "unbounded badge control", badge: true, control: true }
            ];
        }

        function test_hidden_decoder(row) {
            const look = frame.look;
            const altered = row.control ? alteredMeasure(look, "sourceSize: Qt.size(decodeSize, decodeSize)", "sourceSize: Qt.size(0, 0)") : null;
            const measure = altered !== null ? altered.measure
                : shippedMeasure.createObject(scene, { rowCard: measureCard(look) });
            verify(measure !== null);
            try {
                measure.imageStatus(scene.screenshotImage, row.badge);
                const image = measure.imageStates[scene.screenshotImage];
                verify(image !== undefined && !image.visible && !image.cache);
                tryCompare(image, "status", Image.Ready);
                verify(image.implicitWidth > 0 && image.implicitHeight > 0, "positive decoded pixels reach the judge");
                const cap = (row.badge ? look.badge.size : Math.max(look.media.size, look.media.icon)) * scene.Screen.devicePixelRatio;
                if (row.control) {
                    compare(image.implicitWidth, 2560, "the mutation decoded the actual original screenshot");
                    compare(image.implicitHeight, 1440);
                    expectFail("", "the same stored-pixel judge rejects the real unbounded decoder");
                }
                verify(image.implicitWidth <= Math.ceil(cap) && image.implicitHeight <= Math.ceil(cap),
                    "decoded stored pixels stay within the painted owner: " + [image.implicitWidth, image.implicitHeight, cap]);
                if (row.control) return;
                const entry = { key: "decode", app: row.badge ? "Slack" : "VGS", summary: row.badge ? "[workspace] Screenshot" : "Screenshot",
                    body: "A screenshot notification with body text that wraps to another line in the card", image: row.badge ? "" : scene.screenshotImage,
                    workspace: row.badge ? "workspace" : "", workspaceIcon: row.badge ? scene.screenshotImage : "" };
                const card = measuredCard.createObject(scene, { look: look, textColumn: frame.textColumn,
                    app: entry.app, summary: entry.summary, body: entry.body, image: entry.image,
                    workspace: entry.workspace, workspaceIcon: entry.workspaceIcon });
                verify(card !== null);
                try {
                    if (row.badge) tryCompare(card, "showsBadge", true);
                    else tryCompare(card, "showsSlot", true);
                    card.settleHeight();
                    fuzzyCompare(measure.measure(entry, look, card.textColumn), card.fullHeight, 0.5,
                        "bounded resource readiness preserves actual card geometry");
                    const resized = Object.assign({}, look, {
                        badge: Object.assign({}, look.badge, { size: look.badge.size * 2 }),
                        media: Object.assign({}, look.media, { size: look.media.size * 2, icon: look.media.icon * 2 })
                    });
                    card.look = resized;
                    measure.measure(entry, resized, card.textColumn);
                    tryCompare(image, "status", Image.Ready);
                    tryCompare(image, "implicitWidth", Math.round(cap * 2));
                    verify(image.implicitWidth <= Math.ceil(cap * 2) && image.implicitHeight <= Math.ceil(cap * 2));
                    if (row.badge) tryCompare(card, "showsBadge", true);
                    card.settleHeight();
                    fuzzyCompare(measure.measure(entry, resized, card.textColumn), card.fullHeight, 0.5);
                } finally { card.destroy(); }
            } finally {
                if (altered !== null) altered.owner.destroy();
                else measure.destroy();
            }
        }

        function test_shipped_panel_boundary_data() {
            return [
                { tag: "top end", progress: 0, height: 300 },
                { tag: "mid scroll", progress: 0.5, height: 300 },
                { tag: "short top end", progress: 0, height: 180 },
                { tag: "short mid scroll", progress: 0.5, height: 180 },
                // The top band grows in across the gutter as the view
                // leaves its start, so a view that has just left it has
                // barely begun to fade.
                { tag: "just left the top", offset: 1, height: 300, growing: true }
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
            if (rest) {
                const first = parts.faceAt(0);
                const second = parts.faceAt(1);
                verify(first !== undefined && second !== undefined);
                fuzzyCompare(first.mapToItem(panel, 0, 0).y, parts.headerBottom + parts.gutter, 0.5,
                    "at rest the selected first card stands the card gap under the header");
                fuzzyCompare(second.mapToItem(panel, 0, 0).y, first.mapToItem(panel, 0, first.height).y + panel.look.card.gap, 0.5,
                    "the selected first card stands the card gap above the next");
            }
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
                const band = Math.ceil(scroll.topExtent);
                for (const distance of [1, 8, 15]) {
                    compare(painted.red(x, edge - distance), 0, "no painted card strip escapes above the header's bottom edge");
                    compare(painted.blue(x, edge - distance), 0);
                }
                if (rest) {
                    // The top band has no strength at the view's start:
                    // the gutter and the first card paint in full, down
                    // to the bottom band.
                    for (let y = edge + 1; y < edge + view.height - Math.ceil(scroll.fadeExtent); y += 2)
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
            const face = bringRowIntoView(parts, 6);
            const slot = parts.slots[6];
            const list = slot.parent;
            if (row.keyboard) panel.selectIndex(6);
            // Place the card's face in the band: its top just under the
            // header's edge, or its bottom just above the view's bottom.
            const faceTop = row.top ? 2 : view.height - face.height - 2;
            view.contentY = face.mapToItem(view.contentItem, 0, 0).y - faceTop;
            const band = row.top ? parts.scroll.topExtent : parts.scroll.fadeExtent;
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
            const band = parts.scroll.topExtent;
            verify(band > 2 * parts.gutter, "the band is taller than the gutter: " + [band, parts.gutter]);
            const faded = bringRowIntoView(parts, 5);
            view.contentY = faded.mapToItem(view.contentItem, 0, faded.height / 2).y - band / 2;
            verify(view.contentY >= band && view.contentY < view.contentHeight - view.height);
            const clear = parts.faces.find(face => {
                const top = parts.slotOf(face).mapToItem(view, 0, 0).y;
                return top >= band && top + parts.slotOf(face).height <= view.height - band;
            });
            verify(clear !== undefined, "a card stands between the bands");
            const inks = [inkOver(parts.slots[5]), inkOver(parts.slotOf(clear))];
            try {
                const painted = grabPanel();
                const x = Math.floor(parts.slots[5].mapToItem(scene, parts.slots[5].width / 2, 0).x);
                const middle = face => painted.red(x, Math.floor(face.mapToItem(scene, 0, face.height / 2).y));
                compare(middle(clear), 255, "a card between the bands paints in full");
                verify(middle(faded) >= 95 && middle(faded) <= 160,
                    "a card halfway through the top band is half faded: " + middle(faded));
            } finally {
                inks.forEach(ink => ink.destroy());
            }
        }

        function test_every_row_meets_the_same_band_data() {
            return [
                { tag: "top, slot at the header", top: true, past: 0 },
                { tag: "top, slot under the header", top: true, past: 12 },
                { tag: "bottom, slot at the view's end", top: false, past: 0 },
                { tag: "bottom, slot past the view's end", top: false, past: 12 }
            ];
        }

        // Rows 1, 2 and 3 each scrolled the same distance past the header
        // paint the same fade over their slots, row by row of the view, and
        // the band ends at the look's header fade height for each. Three
        // rows placed alike at the bottom edge paint the bottom band, the
        // look's fade height tall, half faded at its middle. Test ink stands
        // in for the card, so the pixels read the mask alone.
        function test_every_row_meets_the_same_band(row) {
            const parts = showPanel(440);
            const view = parts.view;
            const travel = view.contentHeight - view.height;
            const expected = row.top ? panel.look.stack.headerFadeHeight : panel.look.stack.fadeHeight;
            verify(expected < view.height / 2, "the band fits the view: " + [expected, view.height]);
            const profiles = [];
            for (const index of row.top ? [0, 1, 2] : [5, 6, 7]) {
                const slot = parts.slots[index];
                const slotTop = slot.mapToItem(view.contentItem, 0, 0).y;
                view.contentY = row.top ? slotTop + row.past : slotTop + slot.height - row.past - view.height;
                verify(view.contentY > 0 && travel - view.contentY >= expected, "row " + (index + 1) + " lies inside the travel");
                // Ink over the slot, and at the bottom over the content
                // above it across the band.
                const slotX = slot.mapToItem(view.contentItem, 0, 0).x;
                const inkTop = row.top ? slotTop : slotTop + slot.height - row.past - expected - 8;
                verify(!row.top || slot.height >= row.past + expected + 4, "the slot covers the band");
                const ink = boundaryInk.createObject(view.contentItem, { x: slotX, y: inkTop, width: slot.width, height: slotTop + slot.height - inkTop });
                verify(ink !== null);
                try {
                    const painted = grabPanel();
                    const x = Math.floor(slot.mapToItem(scene, slot.width / 2, 0).x);
                    const edge = row.top ? Math.floor(view.mapToItem(scene, 0, 0).y) : Math.ceil(view.mapToItem(scene, 0, view.height).y) - 1;
                    const profile = [];
                    for (let depth = 1; depth <= expected + 4; depth++)
                        profile.push(painted.red(x, row.top ? edge + depth : edge - depth));
                    profiles.push({ row: index + 1, values: profile, end: profile.findIndex((value, at) => profile.slice(at).every(rest => rest >= 254)) + 1 });
                } finally {
                    ink.destroy();
                }
            }
            // Qt's MultiEffect smoothsteps the mask's alpha, so the band's
            // last tenth already paints full ink.
            for (const profile of profiles) {
                verify(profile.end >= expected * 0.9 && profile.end <= expected + 1,
                    "row " + profile.row + "'s band ends at the look's height: " + [profile.end, expected]);
                verify(Math.abs(profile.end - profiles[0].end) <= 1,
                    "row " + profile.row + "'s band matches row " + profiles[0].row + "'s: " + [profile.end, profiles[0].end]);
                const middle = profile.values[Math.round(expected / 2) - 1];
                verify(middle >= 95 && middle <= 160, "row " + profile.row + " is half faded halfway through the band: " + middle);
                profile.values.forEach((value, at) => verify(Math.abs(value - profiles[0].values[at]) <= 2,
                    "row " + profile.row + " paints as row " + profiles[0].row + " does at depth " + (at + 1) + ": " + [value, profiles[0].values[at]]));
            }
        }

        // A pointer swept in 1 px steps from the middle of one card down
        // across the gap into the next: the hover passes from the first
        // card to the second once, and no step reads neither or both.
        function test_pointer_crosses_the_gap_once() {
            const parts = showPanel(600);
            const upper = parts.faceAt(1);
            const lower = parts.faceAt(2);
            const x = parts.slots[1].mapToItem(panel, parts.slots[1].width / 2, 0).x;
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
            const list = parts.slots[0].parent;
            verify(parts.slots.every(slot => slot.height <= view.height - 2 * parts.scroll.fadeExtent),
                "every card fits between the bands");
            list.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(list, "activeFocus", true);
            const check = (index, key) => {
                compare(panel.currentIndex, index);
                waitViewport(parts);
                const slot = parts.slots[index];
                verify(parts.faceAt(index) !== undefined, key + " reveals the actual selected card");
                const top = slot.mapToItem(view.contentItem, 0, 0).y;
                const travel = view.contentHeight - view.height;
                verify(top >= view.contentY + parts.scroll.fadeExtent - 0.5 || view.contentY <= 0,
                    key + " " + index + " leaves the card in the top band: " + [top, view.contentY]);
                verify(top + slot.height <= view.contentY + view.height - parts.scroll.fadeExtent + 0.5 || view.contentY >= travel - 0.5,
                    key + " " + index + " leaves the card in the bottom band: " + [top + slot.height, view.contentY]);
                const ink = inkOver(slot);
                try {
                    const painted = grabPanel();
                    const face = parts.faceAt(index);
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
            verify(renderedFrame(frame));
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
            verify(renderedFrame(frame));
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
