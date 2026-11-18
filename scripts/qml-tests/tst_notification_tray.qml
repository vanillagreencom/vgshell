import QtQuick
import QtQuick.Window
import QtTest
import qs.Unit
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// Actions overlay the resting text geometry. The real text objects keep
// their width, position and line count while the row appears and leaves;
// native Text widths and pixels establish complete labels and the gradient.
Item {
    id: scene
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property real textColumn: Math.ceil(Inset.clearing(look.card.pad, look.radius.full, look.card.width, look.card.maxHeight, look.radius.clearance, look.card.pad))
    width: look.card.width
    height: look.card.maxHeight
    Rectangle { id: ground; anchors.fill: parent; color: scene.look.card.base }
    Component { id: shippedCard; Notifications.NotificationCard {} }
    Component { id: shippedFace; Notifications.CardFace {} }
    // Paint the existing text-layer bounds from a non-layout child so
    // probing its two-dimensional alpha cannot change the measured size.
    Component { id: markerInk; Rectangle { x: -parent.x; y: -parent.y; width: parent.parent.width; height: parent.parent.height; color: "#ff00ff" } }
    Component { id: overflowInk; Rectangle { width: parent.width; height: 1; y: parent.height + 2; color: "#ff00ff" } }

    UnitCase {
        name: "notification_tray"
        when: windowShown
        function actions(count) {
            return count === 3 ? [
                { id: "open", label: "Open recording" },
                { id: "folder", label: "Show in folder" },
                { id: "dismiss", label: "Dismiss" }
            ] : [
                { id: "sync", label: "Set up two-way sync" },
                { id: "open", label: "Open recording" },
                { id: "folder", label: "Show in folder" },
                { id: "copy", label: "Copy link" },
                { id: "dismiss", label: "Dismiss" }
            ];
        }

        function build(component) {
            const card = component.createObject(scene, {
                look: scene.look, textColumn: scene.textColumn,
                summary: "A sender title that is longer than one line with every action shown",
                body: "MMMMM MMMMM MMMMM MMMMM MMMMM MMMMM MMMMM MMMMM ".repeat(8),
                hintIcon: "bell", actions: actions(5)
            });
            verify(card !== null, "the shipped card builds");
            card.anchors.centerIn = scene;
            return card;
        }

        function alteredCard(needle, replacement) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.notifications/NotificationCard.qml"), false);
            request.send();
            const source = request.responseText;
            compare(source.split(needle).length, 2, "the control matches its production owner once");
            const planted = source.replace(needle, replacement);
            verify(planted !== source);
            const at = planted.search(/^Item \{$/m);
            verify(at > 0);
            const wrapper = planted.slice(0, at) + "Item {\n    component ControlCard: " + planted.slice(at)
                + "\n    readonly property Component card: Component { ControlCard {} }\n}\n";
            const holder = Qt.createQmlObject(wrapper, scene, Qt.resolvedUrl("../../shell/plugins/vgs.notifications/OverlayControl.qml"));
            verify(holder !== null);
            const card = build(holder.card);
            card.Component.onDestruction.connect(holder, holder.destroy);
            return card;
        }

        function descendants(item) {
            const found = [];
            for (const child of item.children) found.push(child, ...descendants(child));
            return found;
        }
        function parts(card) {
            const title = findChild(card, "notificationTitleText");
            const body = findChild(card, "notificationBodyText");
            const tray = findChild(card, "notificationCaption").parent;
            verify(title !== null && body !== null && tray !== null);
            return { title: title, body: body, tray: tray };
        }
        function geometry(card) {
            const part = parts(card);
            const values = [card.width, card.height];
            for (const item of [part.title, part.body]) {
                const at = item.mapToItem(card, 0, 0);
                values.push(at.x, at.y, item.width, item.height, item.lineCount);
            }
            return values;
        }
        function pills(card) { return descendants(parts(card).tray).filter(child => child.emphasized !== undefined); }
        function labelsWhole(card) {
            return pills(card).every(pill => {
                const label = pill.contentItem;
                const at = label.mapToItem(card, 0, 0);
                return label instanceof Text && !label.truncated && label.width >= label.implicitWidth
                    && at.x >= 0 && at.x + label.width <= card.width
                    && at.y >= 0 && at.y + label.height <= card.height;
            });
        }
        function test_actions_overlay_unchanged_bounded_text_data() {
            const rows = [];
            for (const mode of ["dark", "light"])
                for (const test of [
                    { name: "three full labels", count: 3, control: "" },
                    { name: "five actions", count: 5, control: "" },
                    { name: "narrowed-text control", count: 5, control: "geometry" },
                    { name: "capped-label control", count: 5, control: "labels" }
                ]) rows.push({ tag: mode + "/" + test.name, mode: mode, count: test.count, control: test.control });
            return rows;
        }
        function test_actions_overlay_unchanged_bounded_text(row) {
            compare(UnitTheme.override({ scheme: { mode: row.mode }, motion: { scale: 0 } }), "ok");
            const card = row.control === "geometry"
                ? alteredCard("            Layout.fillHeight: false", "            Layout.fillHeight: false\n            Layout.rightMargin: card.trayShown ? card.contentWidth / 2 : 0")
                : row.control === "labels"
                    ? alteredCard('                    text: overflow ? "…" : senderAction.label', '                    text: overflow ? "…" : senderAction.label\n                    width: Math.min(implicitWidth, card.contentWidth / 6)')
                    : build(shippedCard);
            try {
                card.actions = actions(row.count);
                card.settleHeight();
                verify(renderedFrame(card));
                const before = geometry(card);
                const part = parts(card);
                compare(part.title.lineCount, 1);
                compare(part.body.lineCount, 2);
                verify(part.title.truncated && part.body.truncated);
                card.showActions = true;
                tryCompare(part.tray, "opacity", 1);
                card.settleHeight();
                verify(renderedFrame(card));
                const shownGeometry = geometry(card);
                if (row.control === "geometry") expectFail("", "an action-dependent column must change resting geometry");
                compare(shownGeometry, before, "actions keep every title/body coordinate and line count");
                if (row.control === "geometry") return;
                compare(pills(card).length, 3);
                compare(pills(card).map(pill => pill.contentItem.text), row.count === 5
                    ? card.actions.slice(0, 2).map(action => action.label).concat(["…"])
                    : card.actions.map(action => action.label), "the native painted words are the sender's full labels");
                const wholeLabels = labelsWhole(card);
                if (row.control === "labels") expectFail("", "the old width cap cannot contain a complete painted label");
                compare(wholeLabels, true, "every native label is whole and inside the card");
                if (row.control === "labels") return;
                const media = findChild(card, "notificationMediaSlot");
                const mediaAt = media.mapToItem(card, 0, media.height / 2);
                fuzzyCompare(mediaAt.y, card.height / 2, 0.5);
                fuzzyCompare(part.tray.y + part.tray.height / 2, card.height / 2, 0.5);
                if (row.count === 5) {
                    const menu = findChild(card, "notificationOverflowMenu");
                    compare(pills(card)[2].text, "…");
                    mouseClick(pills(card)[2]);
                    tryCompare(menu, "opened", true);
                    compare(menu.anchorItem, pills(card)[2]);
                    compare(menu.items().map(item => item.text), card.actions.slice(2).map(action => action.label));
                    readyMenu(menu);
                    mouseClick(menu.items()[0]);
                    tryCompare(menu, "opened", false);
                }
                card.showActions = false;
                tryCompare(part.tray, "opacity", 0);
                card.settleHeight();
                compare(geometry(card), before, "leaving actions restore no different text geometry");
            } finally {
                card.destroy();
                UnitTheme.reset();
            }
        }

        function test_action_mask_fades_only_text_alpha_data() {
            const rows = [];
            for (const mode of ["dark", "light"])
                for (const control of ["", "hard-edge", "clipped-ink", "hidden-text", "missing-mask", "flat-vertical"])
                    rows.push({ tag: mode + "/" + control, mode: mode, control: control });
            return rows;
        }

        // MultiEffect's mask is a smoothstep, not direct alpha. For the
        // card's threshold 0.5 and spread 1, Qt 6.12 derives these bounds.
        // https://github.com/qt/qtdeclarative/blob/v6.12.0/src/effects/qquickmultieffect.cpp#L1443
        // https://github.com/qt/qtdeclarative/blob/v6.12.0/src/effects/data/shaders/multieffect.frag#L99
        function maskedChannel(alpha) {
            const t = Math.max(0, Math.min(1, (alpha - 0.0001) / 1.0001));
            return 255 * t * t * (3 - 2 * t);
        }

        function test_action_mask_fades_only_text_alpha(row) {
            compare(UnitTheme.override({ scheme: { mode: row.mode }, motion: { scale: 0 } }), "ok");
            ground.color = "#000000";
            const card = row.control === "hard-edge"
                ? alteredCard("position: actionMask.fadeStart;", "position: actionMask.fadeEnd;")
                : row.control === "clipped-ink"
                    ? alteredCard("paddingRect: Qt.rect(card.pad, card.pad, card.pad, card.pad)", "paddingRect: Qt.rect(0, 0, 0, 0)")
                    : row.control === "hidden-text"
                        ? alteredCard("1 - tray.opacity * (1 - card.look.tray.fadeAlpha)", "1 - tray.opacity")
                        : row.control === "missing-mask"
                            ? alteredCard("            layer.enabled: card.visible && tray.visible", "            layer.enabled: false && card.visible && tray.visible")
                            : row.control === "flat-vertical"
                                ? alteredCard("            Rectangle {\n                anchors.fill: parent\n                gradient: Gradient {", "            Rectangle {\n                opacity: 0\n                anchors.fill: parent\n                gradient: Gradient {") : build(shippedCard);
            try {
                // The recording worker's actual Open/Show actions and the
                // shell Dismiss leave original ink before the fade band.
                // The separate full-label table covers the longest row.
                card.actions = [
                    { id: "open", label: "Open" },
                    { id: "show", label: "Show" },
                    { id: "dismiss", label: "Dismiss" }
                ];
                card.showActions = true;
                const part = parts(card);
                tryCompare(part.tray, "opacity", 1);
                card.settleHeight();
                const ink = markerInk.createObject(part.body);
                verify(ink !== null);
                // ImageText's link underline paints below its line box.
                // A marker in that existing clearance reads the layer's
                // capture boundary without depending on the font's glyphs.
                verify(overflowInk.createObject(part.body) !== null);
                for (const pill of pills(card)) pill.opacity = 0;
                verify(renderedFrame(card));
                const image = grabImage(scene);
                const below = part.body.mapToItem(scene, 1, part.body.height + 2);
                const rowAt = part.tray.mapToItem(scene, 0, 0);
                verify(below.x >= 0 && below.x < scene.width && below.y >= 0 && Math.ceil(below.y) < scene.height,
                    "the overflow probe is inside the captured scene");
                verify(below.x < rowAt.x - card.look.tray.fadeWidth, "the overflow marker is before the action fade");
                const layer = part.body.parent;
                const layerAt = layer.mapToItem(scene, 0, 0);
                const y = Math.floor(rowAt.y + part.tray.height / 2);
                const top = Math.floor(rowAt.y - 1);
                const bottom = Math.ceil(rowAt.y + part.tray.height + 1);
                const x = Math.floor(rowAt.x - card.look.tray.fadeWidth / 2);
                const behindX = Math.ceil(rowAt.x + 2);
                const beforeX = Math.floor(rowAt.x - card.look.tray.fadeWidth - 2);
                verify(beforeX >= layerAt.x && behindX < layerAt.x + layer.width
                    && top >= layerAt.y && bottom < layerAt.y + layer.height,
                    "every alpha probe is inside the marker ink");
                const expected = {
                    behind: maskedChannel(card.look.tray.fadeAlpha),
                    middle: maskedChannel((1 + card.look.tray.fadeAlpha) / 2)
                };
                verify(expected.behind > 0 && expected.behind < 255, "the look keeps faint original ink behind buttons");
                const observed = {
                    overflow: image.red(Math.floor(below.x), Math.ceil(below.y)),
                    behind: image.red(behindX, y),
                    middle: image.red(x, y),
                    green: image.green(x, y),
                    blue: image.blue(x, y),
                    before: image.red(beforeX, y),
                    top: image.red(behindX, top),
                    bottom: image.red(behindX, bottom)
                };
                // A planted defect can break more than one alpha reading.
                // Judge the complete observation once, after all reads,
                // so an earlier scalar cannot consume a later control.
                const contract = {
                    clearance: observed.overflow > 0,
                    faintCentre: Math.abs(observed.behind - expected.behind) <= 12,
                    softHorizontalBand: Math.abs(observed.middle - expected.middle) <= 12,
                    alphaOnly: observed.green === 0 && observed.blue === observed.middle,
                    originalInk: observed.before === 255,
                    verticalRecovery: Math.min(observed.top, observed.bottom) > observed.behind + (255 - observed.behind) / 2
                };
                if (row.control !== "") expectFail("", row.control + " breaks the rendered text-alpha contract");
                compare(contract, {
                    clearance: true, faintCentre: true, softHorizontalBand: true,
                    alphaOnly: true, originalInk: true, verticalRecovery: true
                }, "text-alpha readings " + JSON.stringify({ observed: observed, expected: expected }));
            } finally {
                card.destroy();
                ground.color = Qt.binding(() => scene.look.card.base);
                UnitTheme.reset();
            }
        }

        function test_toast_holds_its_lifetime_until_the_action_menu_closes_data() {
            return [{ tag: "menu closes", destroy: false }, { tag: "card is destroyed", destroy: true }];
        }

        function test_toast_holds_its_lifetime_until_the_action_menu_closes(row) {
            mouseMove(scene, scene.width - 1, scene.height - 1);
            const face = shippedFace.createObject(scene, { look: scene.look, textColumn: scene.textColumn,
                key: "held-menu", summary: "A notification", actions: Array.from({ length: 5 }, (_, index) => ({ id: "a" + index, label: "Action " + index })) });
            verify(face !== null);
            const holds = [];
            face.hoverRequested.connect((key, held) => holds.push([key, held]));
            face.hovered = true;
            face.showActions = true;
            tryCompare(parts(face.card).tray, "opacity", 1);
            compare(face.hoverReported, true);
            face.card.activateAction(2, "pointer");
            const menu = findChild(face.card, "notificationOverflowMenu");
            tryCompare(menu, "opened", true);
            compare(menu.anchorItem, findChild(face.card, "notificationAction2"));
            face.hovered = false;
            compare(face.hoverReported, true, "the menu retains the same service hover hold");
            if (row.destroy) {
                face.destroy();
                tryVerify(() => holds.length === 2);
            } else {
                menu.close();
                tryCompare(face, "hoverReported", false);
                face.destroy();
            }
            compare(holds, [["held-menu", true], ["held-menu", false]]);
        }

        // Activate the stand-in popup's native window and ask UnitCase
        // for its first frame before sending input.
        function readyMenu(menu) {
            const scope = menu.surface.scope;
            scope.Window.window.requestActivate();
            scope.forceActiveFocus();
            tryCompare(scope.Window, "active", true);
            tryCompare(scope, "activeFocus", true);
            verify(renderedFrame(menu.surface.contentItem));
        }

    }
}
