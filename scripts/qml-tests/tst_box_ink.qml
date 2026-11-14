import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// Read the pixels of the shipped boxes, not the inset calculation. Text
// fills its natural width so unused line width is not counted as padding.
// CodeLine's optional Copy control and the OSD's level bar are hidden in
// the text-only rows; their normal compositions are covered below too.
// A capsule notification keeps its intentional extra side clearance.
Item {
    id: fixtureRoot
    width: 800
    height: 600
    property string words: "TTTTTTTT"
    property string paneKind: "panel"
    property bool bodyNote: false
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    function descendants(item) {
        return Array.from(item.children).reduce((out, child) => out.concat([child], descendants(child)), []);
    }
    Rectangle { anchors.fill: parent; color: "#101010"; z: -1 }

    Component { id: cardBox; Card { width: sample.implicitWidth + 24; Label { id: sample; text: fixtureRoot.words } } }
    Component {
        id: paneBox
        Item {
            width: sample.implicitWidth + 2 * layout.padding
            height: layout.implicitHeight
            Rectangle { anchors.fill: parent; color: "#101010" }
            Pane {
                id: layout
                width: parent.width
                container: fixtureRoot.paneKind
                fitToContent: true
                Label { id: sample; text: fixtureRoot.words }
            }
        }
    }
    Component {
        id: calloutBox
        Callout {
            text: fixtureRoot.words
            color: "#101010"
            width: measure.implicitWidth + 24
            Label { id: measure; visible: false; text: fixtureRoot.words }
        }
    }
    Component {
        id: codeBox
        CodeLine {
            text: fixtureRoot.words
            width: measure.implicitWidth + 16
            Component.onCompleted: { copyButton.visible = false; }
            Label { id: measure; visible: false; role: "code"; text: fixtureRoot.words }
        }
    }
    Component {
        id: osdBox
        LevelOsd {
            text: fixtureRoot.words
            Component.onCompleted: {
                const row = fixtureRoot.descendants(this).find(child => child instanceof Row);
                row.children.find(child => child.value !== undefined).visible = false;
            }
        }
    }
    Component {
        id: notificationBox
        Item {
            id: holder
            readonly property var ownLook: {
                const value = JSON.parse(JSON.stringify(fixtureRoot.look));
                value.card.width = Math.ceil(measure.implicitWidth) + 40;
                value.text.title.size = Theme.text.body.size;
                value.text.body.size = Theme.text.body.size;
                return value;
            }
            width: card.width
            height: card.height
            Rectangle { anchors.fill: parent; color: "#101010" }
            Notifications.CardScroll {
                id: scrollMeasure
                visible: false
                look: holder.ownLook
            }
            Label {
                id: measure
                visible: false
                text: fixtureRoot.words
                font.family: fixtureRoot.look.font.family.sans
                font.weight: fixtureRoot.bodyNote ? 400 : 700
                font.variableAxes: ({})
            }
            Notifications.NotificationCard {
                id: card
                look: holder.ownLook
                open: true
                textColumn: scrollMeasure.textColumn
                summary: fixtureRoot.bodyNote ? "" : fixtureRoot.words
                body: fixtureRoot.bodyNote ? fixtureRoot.words : ""
            }
        }
    }
    Component {
        id: tipBox
        Item {
            width: 40; height: 20
            property alias tip: tip
            Tooltip { id: tip; text: fixtureRoot.words; shown: true }
        }
    }
    Component {
        id: headerBox
        Pane {
            width: 360
            fitToContent: true
            container: "window"
            header: Row {
                Label { text: "Plugins"; role: "windowTitle"; y: topForCapCenter(32) }
                Button { text: "Add plugin" }
            }
        }
    }
    Component {
        id: roundedProbe
        Rectangle {
            width: 80; height: 48; radius: 24; color: "#404040"
            Rectangle { x: 12; y: 12; width: 56; height: 24; color: "#ffffff" }
        }
    }

    UnitCase {
        name: "box_ink"
        when: windowShown

        function init() {
            void Theme.card;
            UnitTheme.reset();
            compare(UnitTheme.override({ palette: { background: "#101010", foreground: "#ffffff" }, motion: { scale: 0 } }), "ok");
        }
        function cleanup() { UnitTheme.reset(); }

        function test_equal_drawn_gaps_data() {
            const rows = [];
            for (const size of [15, 20])
                for (const lines of [1, 2])
                    for (const box of [
                        { name: "Card", component: cardBox, pad: 12 },
                        { name: "window", component: paneBox, pad: 16 },
                        { name: "dialog", component: paneBox, pad: 16 },
                        { name: "popover", component: paneBox, pad: 12 },
                        { name: "panel", component: paneBox, pad: 12 },
                        { name: "Callout", component: calloutBox, pad: 12 },
                        { name: "CodeLine", component: codeBox, pad: 8 },
                        { name: "OSD", component: osdBox, pad: 12 },
                        { name: "Tooltip", component: tipBox, pad: 8 },
                        { name: "notification", component: notificationBox, pad: 14, side: 20 },
                        { name: "notification-body", component: notificationBox, pad: 14, side: 20 }
                    ])
                        rows.push({ tag: box.name + "/" + size + "/" + lines, box: box, size: size, lines: lines });
            return rows;
        }

        function bounds(image, ground) {
            let left = image.width, top = image.height, right = -1, bottom = -1;
            // Count antialiased edge ink above one eighth of the contrast
            // to the actual ground at that pixel. GlassSurface's outline
            // is brighter than its flat fill on OSD and Tooltip. A single
            // fill sample therefore counts the whole outline as text.
            for (let y = 0; y < image.height; y++)
                for (let x = 0; x < image.width; x++)
                    if (image.red(x, y) > ground.red(x, y) + (255 - ground.red(x, y)) / 8
                        && image.green(x, y) > ground.green(x, y) + (255 - ground.green(x, y)) / 8
                        && image.blue(x, y) > ground.blue(x, y) + (255 - ground.blue(x, y)) / 8
                        && image.alpha(x, y) > 160) {
                        left = Math.min(left, x); right = Math.max(right, x);
                        top = Math.min(top, y); bottom = Math.max(bottom, y);
                    }
            return right < 0 ? null : [left, top, image.width - 1 - right, image.height - 1 - bottom];
        }

        function foregroundBounds(box, foreground) {
            const image = grabImage(box);
            const opacities = foreground.map(item => item.opacity);
            try {
                // Opacity preserves positioner participation and geometry:
                // https://doc.qt.io/qt-6/qml-qtquick-item.html#opacity-prop
                foreground.forEach(item => { item.opacity = 0; });
                verify(renderedFrame(box));
                return bounds(image, grabImage(box));
            } finally {
                foreground.forEach((item, i) => { item.opacity = opacities[i]; });
            }
        }

        function test_probe_separates_rounded_fill_from_foreground() {
            const box = createTemporaryObject(roundedProbe, fixtureRoot);
            verify(renderedFrame(box));
            compare(foregroundBounds(box, [box.children[0]]).join(","), "12,12,12,12");
            box.children[0].opacity = 0;
            verify(renderedFrame(box));
            compare(foregroundBounds(box, [box.children[0]]), null, "rounded fill alone is not ink");
        }

        function test_equal_drawn_gaps(data) {
            fixtureRoot.words = data.lines === 1 ? "TTTTTTTT" : "TTTTTTTT\nTTTTTTTT";
            fixtureRoot.paneKind = data.box.name;
            fixtureRoot.bodyNote = data.box.name === "notification-body";
            compare(UnitTheme.override({ font: { size: data.size }, palette: { background: "#101010", foreground: "#ffffff" }, motion: { scale: 0 } }), "ok");
            const made = createTemporaryObject(data.box.component, fixtureRoot);
            verify(made !== null);
            let box = made;
            if (data.box.name === "Tooltip") {
                tryCompare(made.tip, "opened", true);
                box = made.tip.tracker.popup.contentItem;
            }
            const card = fixtureRoot.descendants(made).find(child => typeof child.settleHeight === "function");
            if (card !== undefined) card.settleHeight();
            verify(renderedFrame(box));
            verify(renderedFrame(box));
            const text = fixtureRoot.descendants(box).filter(item => item instanceof Text && item.visible);
            verify(text.length > 0, "the actual component supplies the foreground");
            const gaps = foregroundBounds(box, text);
            verify(gaps !== null, "content ink is present");
            const side = data.box.side === undefined ? data.box.pad : data.box.side;
            const expected = [side, data.box.pad, side, data.box.pad];
            let geometry = "";
            if (data.tag === "notification/20/2") {
                const title = text.find(item => item.objectName === "notificationTitleText");
                if (title === undefined) {
                    geometry = " geometry=" + JSON.stringify({ unavailable: "notification title is absent" });
                } else {
                    const summary = title.parent;
                    const measure = summary.parent;
                    // Nonvisual objects declared in Item.data also belong
                    // to Item.resources; no production accessor is needed.
                    // https://doc.qt.io/qt-6/qml-qtquick-item.html#resources-prop
                    const clearing = Array.from(measure.resources).find(item => item.content === measure && typeof item.topInk === "number");
                    geometry = " geometry=" + JSON.stringify({
                        preferredTextHeight: measure.implicitHeight, assignedTextHeight: measure.height,
                        measureY: measure.y, summaryY: summary.y, titleY: title.y,
                        titleAtCard: title.mapToItem(card, 0, 0).y,
                        titleHeight: title.height, titleContentHeight: title.contentHeight, titleLines: title.lineCount,
                        titleBaseline: title.baselineOffset, titleLastBaseline: title.lastBaseline(), titleCapTop: title.capTop(),
                        titleInkAbove: title.inkAbove, titleInkBelow: title.inkBelow,
                        measureInkAbove: measure.inkAbove, measureInkBelow: measure.inkBelow,
                        cardHeight: card.height,
                        clearing: clearing === undefined ? { unavailable: "ClearingInset is absent from layout resources" }
                            : { topInk: clearing.topInk, bottomInk: clearing.bottomInk,
                                topPadding: clearing.topPadding, bottomPadding: clearing.bottomPadding }
                    });
                }
            }
            console.log("box-ink: " + data.tag + " gaps=" + gaps + " want=" + expected + geometry);
            for (let i = 0; i < 4; i++)
                fuzzyCompare(gaps[i], expected[i], 1, data.tag + " edge " + i + ": " + gaps);
            const equal = gaps.map((gap, i) => gap - (i % 2 === 0 ? side - data.box.pad : 0));
            verify(Math.max(...equal) - Math.min(...equal) <= 1, data.tag + " four-edge equality: " + gaps);
            if (made.tip !== undefined) made.tip.shown = false;
        }

        // A control's painted box, not the title's leading, owns a header
        // edge. This is the Plugins window's control-centred pattern.
        function test_control_centred_header_keeps_its_inset() {
            const pane = createTemporaryObject(headerBox, fixtureRoot);
            verify(renderedFrame(pane));
            const row = pane.header[0];
            const control = row.children[1];
            compare(control.mapToItem(pane, 0, 0).y, 16);
            fuzzyCompare(row.children[0].y + row.children[0].capCentre, control.height / 2, 1);
        }
    }
}
