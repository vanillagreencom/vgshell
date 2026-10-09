import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// BarItem: every bar widget's one item. It is `bar.item.height` tall and
// never narrower; its content sits `bar.item.paddingX` in; the icon is
// `bar.item.icon` wide at full opacity; a count draws in the bar role in
// the item's tone; a value draws its level's colour and the icon or its
// caption the most severe level shown; the separator draws its own token;
// the item is as wide as its padding and what it draws, with no room
// after the reading; an item whose readings hold samples is as wide as its
// samples shown and draws right aligned in that width, so its glyphs end
// where the same item without held room ends, the item keeps its right
// padding, and the icon or caption stays as far from its value as with no
// held room; a stacked item draws text over count in `bar.stacked.size`,
// both lines inside the item at every item height, left aligned in a
// block whose held width is its wider line's sample, in mixed case under
// an uppercase bar role; with an icon each line draws its own,
// `bar.stacked.icon` at `bar.stacked.iconStroke` in that line's colour,
// centred in the line and `bar.item.gap` before its value at a short
// reading as at the widest, in place of the one icon; with a caption
// each line draws its own label there instead, in that line's colour, in
// one column so both readings start at one edge, and no single caption
// stands before the block; a spinner stays the item gap before the
// block; with one reading shown it stays one line; `active` fills it with `bar.active`; hover and press fill it
// with their own tokens; a click emits `clicked`.
Item {
    id: root
    width: 300
    height: 260

    BarItem { id: icon; iconName: "settings"; label: "Settings"; onClicked: root.clicks += 1 }
    BarItem { id: counted; iconName: "shield"; count: "12"; tone: "#ff0000"; y: 40 }
    BarItem { id: pill; text: "1"; active: true; y: 80 }
    BarItem { id: spinner; iconName: "refresh-cw"; spinning: true; y: 120 }
    BarItem { id: tooltipItem; iconName: "settings"; label: "Settings"; tooltip: "Open settings"; tooltipDetails: ["Pinned in the bar"]; x: 80 }
    property int clicks: 0
    // The held readings draw red on black here, below every other item.
    Rectangle { id: canvas; y: 160; width: root.width; height: 100; color: "black" }
    Component { id: heldCase; BarItem { tone: "#ff0000" } }
    Component { id: readingCase; BarItem { x: 150 } }
    Component { id: stackedCase; BarItem { tone: "#ff0000"; stacked: true; x: 8; y: 16 } }
    Component {
        id: tooltipCase
        BarItem {
            property bool hasDetails: false
            tooltipDetails: hasDetails ? ["Focused workspace"] : []
            x: 180
            y: 80
        }
    }

    TestCase {
        name: "baritem"
        when: windowShown

        function init() { UnitTheme.reset(); root.clicks = 0; }

        function labels(item) {
            const out = [];
            const walk = node => { for (const child of node.children) { if (child.role !== undefined && child.visible) out.push(child); walk(child); } };
            walk(item.contentItem);
            return out;
        }
        function firstIcon(item) {
            const walk = node => { for (const child of node.children) { if (child.name !== undefined && child.paths !== undefined) return child; const found = walk(child); if (found) return found; } return null; };
            return walk(item.contentItem);
        }
        // The icons the stacked lines draw, the text line's first: every
        // shown icon but the item's one icon.
        function lineIcons(item) {
            const glyph = firstIcon(item), out = [];
            const walk = node => { for (const child of node.children) { if (child.paths !== undefined && child !== glyph && child.visible) out.push(child); walk(child); } };
            walk(item.contentItem);
            return out;
        }

        function test_geometry_follows_the_bar_item_tokens() {
            compare(icon.height, Theme.bar.item.height);
            compare(icon.width, Theme.bar.item.height, "an icon-only item is square");
            compare(counted.leftPadding, Theme.bar.item.paddingX);
            compare(counted.width, Math.ceil(counted.implicitContentWidth) + 2 * Theme.bar.item.paddingX);
            compare(firstIcon(icon).size, Theme.bar.item.icon);
            compare(firstIcon(icon).opacity, 1);
            const glyph = firstIcon(icon);
            fuzzyCompare(glyph.mapToItem(icon, 0, 0).y + glyph.height / 2, icon.height / 2, 0.5);
        }

        function test_count_draws_in_the_bar_role_and_the_tone() {
            const found = labels(counted);
            compare(found.length, 1);
            compare(found[0].role, "bar");
            compare(found[0].text, "12");
            compare(String(found[0].color), "#ff0000");
            compare(String(firstIcon(counted).color), "#ff0000");
        }

        function test_active_fills_and_states_move_the_fill() {
            compare(String(pill.background.color), String(Qt.color(Theme.bar.active)));
            compare(String(labels(pill)[0].color), String(Qt.color(Theme.bar.onActive)));
            mouseMove(icon, icon.width / 2, icon.height / 2);
            tryCompare(icon.background, "color", Qt.color(Theme.bar.item.hover));
            mousePress(icon, icon.width / 2, icon.height / 2);
            tryCompare(icon.background, "color", Qt.color(Theme.bar.item.pressed));
            mouseRelease(icon, icon.width / 2, icon.height / 2);
            compare(root.clicks, 1);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(icon.background, "color", Qt.color("transparent"));
        }

        function test_a_spinner_takes_the_icon_place() {
            const glyph = firstIcon(spinner);
            compare(glyph.visible, false);
            compare(spinner.width, spinner.height);
        }

        function test_tooltip_is_anchored_to_the_item() {
            const tip = tooltipItem.children.find(child => child.details !== undefined);
            verify(tip !== undefined, "the bar item has one tooltip");
            compare(tip.anchorItem, tooltipItem);
            compare(tip.text, "Open settings");
            compare(JSON.stringify(tip.details), JSON.stringify(["Pinned in the bar"]));
        }

        // Workspaces supplies text alone; Gallery's counted Agent Warden
        // supplies a distinct label. Explicit titles and details stay owned
        // by their caller, even when the title repeats the visible text.
        function test_tooltip_presence_data() {
            return [
                { tag: "workspace", properties: { text: "1" }, title: "", present: false },
                { tag: "icon-only", properties: { iconName: "settings", label: "Settings" }, title: "Settings", present: true },
                { tag: "explicit", properties: { text: "1", tooltip: "Workspace one" }, title: "Workspace one", present: true },
                { tag: "explicit-repeat", properties: { text: "1", tooltip: "1" }, title: "1", present: true },
                { tag: "details", properties: { text: "1", hasDetails: true }, title: "1", present: true },
                { tag: "count-name", properties: { iconName: "shield", count: "2", label: "Agent Warden" }, title: "Agent Warden", present: true },
                { tag: "count-repeat", properties: { count: "2", label: "2" }, title: "", present: false }
            ];
        }

        function test_tooltip_presence(data) {
            const item = createTemporaryObject(tooltipCase, root, data.properties);
            verify(item !== null);
            const tip = item.children.find(child => child.details !== undefined);
            verify(tip !== undefined);
            compare(typeof tip.text, "string");
            compare(tip.text, data.title);
            mouseMove(item, item.width / 2, item.height / 2);
            tryCompare(tip.hover, "hovered", true);
            compare(tip.resting, data.present);
            if (data.present) tryCompare(tip, "shown", true);
            else compare(tip.shown, false);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "shown", false);
        }

        // The expected width adds the padding to the drawn labels' own
        // widths, so any room the item keeps beyond them turns this red.
        function test_the_width_ends_at_the_reading_data() {
            return [
                { tag: "text", properties: { text: "5%" } },
                { tag: "icon-text", properties: { iconName: "cpu", text: "100%" } },
                { tag: "icon-separated-count", properties: { iconName: "cpu", text: "5%", count: "54°", separator: "/" } },
                { tag: "icon-spaced-count", properties: { iconName: "cpu", text: "5%", count: "54°" } },
                { tag: "caption-long-reading", properties: { caption: "RAM", text: "999.9 GB", count: "100%", separator: "/" } }
            ];
        }

        function test_the_width_ends_at_the_reading(data) {
            const item = createTemporaryObject(readingCase, root, data.properties);
            verify(item !== null);
            const found = labels(item);
            const shown = [data.properties.caption, data.properties.text, data.properties.separator, data.properties.count]
                .filter(value => value !== undefined && value !== "");
            compare(JSON.stringify(found.map(label => label.text)), JSON.stringify(shown));
            let content = data.properties.iconName === undefined ? 0 : Theme.bar.item.icon;
            if (data.properties.iconName !== undefined || data.properties.caption !== undefined) content += Theme.bar.item.iconGap;
            for (const label of found) content += label.implicitWidth;
            if (data.properties.count !== undefined && data.properties.separator === undefined) content += Theme.bar.item.iconGap;
            // The content row lays out at its next polish.
            tryCompare(item, "implicitWidth", Theme.bar.item.paddingX + Math.ceil(content) + Theme.bar.item.paddingX);
            compare(item.width, item.implicitWidth);
            const last = found[found.length - 1];
            tryVerify(() => item.width - item.rightPadding - last.mapToItem(item, last.width, 0).x < 1, 1000, "the reading ends at the right padding");
        }

        // The rightmost column of `img`, a grab of the root, holding ink
        // inside `item`'s box, -1 when none does.
        function inkRight(img, item) {
            const at = item.mapToItem(root, 0, 0);
            for (let x = Math.min(img.width, Math.ceil(at.x + item.width)) - 1; x >= Math.max(0, Math.floor(at.x)); x--)
                for (let y = Math.max(0, Math.floor(at.y)); y < Math.min(img.height, Math.ceil(at.y + item.height)); y++)
                    if (img.red(x, y) > 64) return x;
            return -1;
        }
        // The blank between the last ink inside `item` and its box's right
        // edge.
        function trailing(img, item) {
            const ink = inkRight(img, item);
            verify(ink >= 0, "\"" + item.text + "\" draws");
            return item.mapToItem(root, item.width, 0).x - (ink + 1);
        }

        // `held` holds a sample, `wide` shows the sample's text with no
        // sample, and `bare` shows the held reading with no sample: the
        // held item is as wide as `wide`, and each held value and the item
        // end their ink where `bare` ends it.
        function test_a_held_reading_draws_right_aligned_data() {
            return [
                { tag: "text", held: { text: "5%", textSample: "100%" }, wide: { text: "100%" }, bare: { text: "5%" } },
                { tag: "count", held: { iconName: "cpu", text: "5%", count: "9°", countSample: "100°", separator: "/" },
                    wide: { iconName: "cpu", text: "5%", count: "100°", separator: "/" }, bare: { iconName: "cpu", text: "5%", count: "9°", separator: "/" } },
                { tag: "both", held: { iconName: "cpu", text: "5%", textSample: "100%", count: "9°", countSample: "100°", separator: "/" },
                    wide: { iconName: "cpu", text: "100%", count: "100°", separator: "/" }, bare: { iconName: "cpu", text: "5%", count: "9°", separator: "/" } },
                { tag: "spaced-count", held: { caption: "RAM", text: "1.0 GB", textSample: "12.0 GB", count: "9%", countSample: "100%" },
                    wide: { caption: "RAM", text: "12.0 GB", count: "100%" }, bare: { caption: "RAM", text: "1.0 GB", count: "9%" } }
            ];
        }

        function test_a_held_reading_draws_right_aligned(data) {
            mouseMove(root, root.width - 1, 0);
            const step = Theme.bar.item.height + 4;
            const held = createTemporaryObject(heldCase, canvas, data.held);
            const bare = createTemporaryObject(heldCase, canvas, Object.assign({ y: step }, data.bare));
            const wide = createTemporaryObject(heldCase, canvas, Object.assign({ y: 2 * step }, data.wide));
            verify(held !== null && bare !== null && wide !== null);
            verify(3 * step <= canvas.height, "the three items fit the canvas");
            tryVerify(() => wide.implicitWidth > bare.implicitWidth, 1000, "the wide reading lays out");
            tryCompare(held, "width", wide.width, 1000, "the held item is as wide as its sample shown");
            verify(waitForRendering(canvas));
            const img = grabImage(root);
            compare(img.width, root.width, "the root grabs at one pixel a point");
            const values = item => labels(item).filter(label => label.text === data.held.text || label.text === data.held.count);
            const heldValues = values(held), bareValues = values(bare);
            compare(heldValues.length, [data.held.text, data.held.count].filter(value => value !== undefined).length);
            compare(bareValues.length, heldValues.length);
            for (let index = 0; index < heldValues.length; index++)
                verify(Math.abs(trailing(img, heldValues[index]) - trailing(img, bareValues[index])) <= 1,
                    "\"" + heldValues[index].text + "\" ends at the right of its held width");
            verify(Math.abs(trailing(img, held) - trailing(img, bare)) <= 1, "the held reading ends at the right padding");
        }

        // The leftmost column of `img` holding ink inside `item`'s box, -1
        // when none does.
        function inkLeft(img, item) {
            const at = item.mapToItem(root, 0, 0);
            for (let x = Math.max(0, Math.floor(at.x)); x < Math.min(img.width, Math.ceil(at.x + item.width)); x++)
                for (let y = Math.max(0, Math.floor(at.y)); y < Math.min(img.height, Math.ceil(at.y + item.height)); y++)
                    if (img.red(x, y) > 64) return x;
            return -1;
        }
        // The values that start a line beside the icon or caption: the
        // text, and stacked, the count too.
        function lineStarts(item) {
            return labels(item).filter(label => label.text === item.text || (item.stackedShown && label.text === item.count));
        }
        // The mark before each value that starts a line: stacked, that
        // line's own icon or label; otherwise the icon or caption.
        function marks(item) {
            const glyph = firstIcon(item);
            return lineStarts(item).map(value => item.lineIcons || item.lineCaptions
                ? value.parent.children.find(child => child !== value && child.visible && (child.paths !== undefined || child.role !== undefined))
                : glyph.parent.visible ? glyph : labels(item)[0]);
        }
        // The blank between each mark's ink and the ink of its value.
        function markGaps(img, item) {
            const found = marks(item);
            return lineStarts(item).map((value, index) => {
                verify(found[index] !== undefined, "\"" + value.text + "\" has its mark");
                const markInk = inkRight(img, found[index]);
                verify(markInk >= 0, "the mark draws");
                const valueInk = inkLeft(img, value);
                verify(valueInk >= 0, "\"" + value.text + "\" draws");
                return valueInk - (markInk + 1);
            });
        }

        // A short and the widest value held at the same sample, on one line
        // and stacked: the held room sits before the icon or caption, so the
        // blank between it and each line's value is the one the same item
        // with no held room draws. Stacked, each line's value starts
        // `bar.item.gap` after its own icon's or label's box, and both
        // marks start at one left edge.
        function test_the_mark_stays_beside_its_value_data() {
            return [
                { tag: "short", held: { iconName: "cpu", text: "9%", textSample: "100%" } },
                { tag: "widest", held: { iconName: "cpu", text: "100%", textSample: "100%" } },
                { tag: "short-count", held: { iconName: "cpu", text: "9%", textSample: "100%", count: "9°", countSample: "100°", separator: "/" } },
                { tag: "short-caption", held: { caption: "RAM", text: "1.0 GB", textSample: "12.0 GB", count: "9%", countSample: "100%" } },
                { tag: "stacked-short", held: { iconName: "cpu", countIconName: "thermometer", text: "3%", textSample: "100%", count: "41°", countSample: "100°", stacked: true } },
                { tag: "stacked-widest", held: { iconName: "cpu", countIconName: "thermometer", text: "100%", textSample: "100%", count: "100°", countSample: "100°", stacked: true } },
                { tag: "stacked-caption", held: { caption: "RAM", countCaption: "SWP", text: "1.0 GB", textSample: "12.0 GB", count: "9%", countSample: "100%", stacked: true } }
            ];
        }

        function test_the_mark_stays_beside_its_value(data) {
            mouseMove(root, root.width - 1, 0);
            const bareProperties = Object.assign({}, data.held, { textSample: "", countSample: "", y: Theme.bar.item.height + 4 });
            const held = createTemporaryObject(heldCase, canvas, data.held);
            const bare = createTemporaryObject(heldCase, canvas, bareProperties);
            verify(held !== null && bare !== null);
            tryVerify(() => held.width >= bare.width && bare.width > bare.height, 1000, "both items lay out");
            verify(waitForRendering(canvas));
            const img = grabImage(root);
            const heldGaps = markGaps(img, held), bareGaps = markGaps(img, bare);
            compare(heldGaps.length, data.held.stacked ? 2 : 1);
            for (let index = 0; index < heldGaps.length; index++)
                verify(Math.abs(heldGaps[index] - bareGaps[index]) <= 1, "the held item keeps its mark beside its value: held " + heldGaps[index] + ", bare " + bareGaps[index]);
            if (data.held.stacked) {
                verify(held.lineIcons || held.lineCaptions, "each stacked line draws its own mark");
                const lineMarks = marks(held);
                for (const [index, value] of lineStarts(held).entries())
                    tryVerify(() => Math.abs(value.mapToItem(held, 0, 0).x - lineMarks[index].mapToItem(held, lineMarks[index].width, 0).x - Theme.bar.item.gap) <= 0.5, 1000,
                        "\"" + value.text + "\" starts the stacked gap after its mark");
                compare(lineMarks[0].mapToItem(held, 0, 0).x, lineMarks[1].mapToItem(held, 0, 0).x, "both line marks start at one left edge");
            }
        }

        function test_the_separated_reading_follows_the_icon() {
            const item = createTemporaryObject(readingCase, root, { iconName: "cpu", text: "5%", count: "9°", separator: "/" });
            const found = labels(item), glyph = firstIcon(item);
            compare(found.length, 3);
            compare(found[1].text, "/");
            tryVerify(() => Math.abs(found[0].mapToItem(item, 0, 0).x - glyph.mapToItem(item, glyph.width, 0).x - Theme.bar.item.iconGap) <= 0.5, 1000, "the drawn reading follows the icon after layout");
            fuzzyCompare(found[1].mapToItem(item, 0, 0).x, found[0].mapToItem(item, found[0].width, 0).x, 0.5);
            fuzzyCompare(found[2].mapToItem(item, 0, 0).x, found[1].mapToItem(item, found[1].width, 0).x, 0.5);
        }

        // Each (text, count) level pair, with and without a count shown: the
        // values draw their own level, the separator draws its own token,
        // and the icon draws the most severe level of the values shown.
        function test_the_icon_draws_the_most_severe_value_data() {
            const order = ["normal", "warning", "danger"];
            const cases = [];
            for (const textLevel of order)
                for (const countLevel of order) {
                    cases.push({ tag: textLevel + "-" + countLevel, textLevel: textLevel, countLevel: countLevel, count: "9°",
                        icon: order[Math.max(order.indexOf(textLevel), order.indexOf(countLevel))] });
                    cases.push({ tag: textLevel + "-" + countLevel + "-hidden-count", textLevel: textLevel, countLevel: countLevel, count: "",
                        icon: textLevel });
                }
            return cases;
        }

        function test_the_icon_draws_the_most_severe_value(data) {
            const tone = "#123456";
            const colours = { normal: Qt.color(tone), warning: Qt.color(Theme.color.warning), danger: Qt.color(Theme.color.danger) };
            const item = createTemporaryObject(readingCase, root, { iconName: "cpu", text: "5%", count: data.count, separator: "/",
                tone: tone, textLevel: data.textLevel, countLevel: data.countLevel });
            verify(item !== null);
            const found = labels(item);
            compare(found[0].color, colours[data.textLevel]);
            if (data.count !== "") {
                compare(found.length, 3);
                compare(found[1].color, Qt.color(Theme.bar.item.separator), "the separator takes no level or tone");
                compare(found[2].color, colours[data.countLevel]);
            } else {
                compare(found.length, 1);
            }
            compare(firstIcon(item).color, colours[data.icon]);
        }

        function test_a_caption_takes_the_icon_place_and_colour() {
            const item = createTemporaryObject(readingCase, root, { iconName: "gpu", caption: "GPU", label: "GPU",
                text: "5%", count: "88°", separator: "/", countLevel: "danger" });
            verify(item !== null);
            const glyph = firstIcon(item);
            compare(glyph.parent.visible, false, "the caption replaces the icon");
            const found = labels(item);
            compare(found[0].text, "GPU");
            compare(found[0].role, "bar");
            compare(found[0].color, Qt.color(Theme.color.danger));
            // anchors.centerIn rounds the row to a whole pixel, so the
            // caption may start up to one pixel past the padding.
            tryVerify(() => Math.abs(found[0].mapToItem(item, 0, 0).x - item.leftPadding) <= 1, 1000, "the caption starts at the padding");
            fuzzyCompare(found[1].mapToItem(item, 0, 0).x - found[0].mapToItem(item, found[0].width, 0).x, Theme.bar.item.iconGap, 0.5);
            const alone = createTemporaryObject(readingCase, root, { caption: "GPU", label: "GPU graphics" });
            compare(alone.iconOnly, false);
            compare(alone.leftPadding, Theme.bar.item.paddingX);
            compare(alone.Accessible.name, "GPU graphics");
            compare(labels(alone)[0].color, Qt.color(Theme.bar.foreground));
        }

        // Stacked readings at item heights around the shipped 24 and an odd
        // one: test-theme-logic.js walks the judge's whole length range for
        // the token arithmetic; this draws the lines. Each line's box and
        // its ink stay inside the item, and the count's line is below the
        // text's. The stacked text follows the item's height, so only the
        // shipped item draws it smaller than the bar text.
        function test_stacked_lines_fit_the_item_data() {
            return [16, 24, 25, 40, 64].map(height => ({ tag: String(height), height: height }));
        }

        function test_stacked_lines_fit_the_item(data) {
            mouseMove(root, root.width - 1, 0);
            compare(UnitTheme.override({ bar: { item: { height: data.height } } }), "ok");
            const item = createTemporaryObject(stackedCase, canvas, { text: "100%", count: "100°", separator: "/" });
            verify(item !== null);
            compare(item.height, data.height);
            verify(item.y + item.height + 16 <= canvas.height, "the canvas holds the item and a margin under it");
            const found = labels(item);
            compare(JSON.stringify(found.map(label => label.text)), JSON.stringify(["100%", "100°"]), "the stacked lines draw no separator");
            for (const label of found) {
                compare(label.font.pixelSize, Theme.bar.stacked.size);
                compare(label.height, Theme.bar.stacked.lineHeight);
            }
            if (data.height === 24) verify(Theme.bar.stacked.size < Theme.text.bar.size, "the shipped stacked text is smaller than the bar text");
            tryVerify(() => found[1].mapToItem(item, 0, 0).y >= found[0].mapToItem(item, 0, found[0].height).y, 1000, "the count's line is under the text's");
            for (const label of found) {
                const top = label.mapToItem(item, 0, 0).y;
                verify(top >= 0 && top + label.height <= item.height, "\"" + label.text + "\" lies inside the item: top " + top + ", height " + label.height);
            }
            verify(waitForRendering(canvas));
            const img = grabImage(root);
            const box = item.mapToItem(root, 0, 0);
            const inkRows = [];
            for (let y = Math.floor(box.y) - 16; y < Math.ceil(box.y + item.height) + 16; y++)
                for (let x = Math.floor(box.x); x < Math.ceil(box.x + item.width); x++)
                    if (img.red(x, y) > 64) { inkRows.push(y); break; }
            verify(inkRows.length > 0, "the stacked lines draw");
            verify(inkRows[0] >= box.y && inkRows[inkRows.length - 1] < box.y + item.height,
                "the ink lies inside the item: rows " + inkRows[0] + " to " + inkRows[inkRows.length - 1] + ", item " + box.y + " to " + (box.y + item.height));
        }

        // The block holds its wider line's sample and the lines left align
        // in it: a value change keeps the item's width, and both lines start
        // at one left edge.
        function test_stacked_lines_hold_their_samples() {
            const item = createTemporaryObject(stackedCase, canvas, { caption: "RAM", countCaption: "SWP", text: "1.0 GB", textSample: "12.0 GB", count: "9%", countSample: "100%" });
            verify(item !== null);
            const found = labels(item).filter(label => label.text === item.text || label.text === item.count);
            compare(found.length, 2);
            tryVerify(() => item.width > item.height, 1000, "the item lays out");
            const width = item.width;
            const starts = () => found.map(label => Math.round(label.mapToItem(item, 0, 0).x));
            compare(starts()[0], starts()[1], "both lines start at one left edge");
            verify(found[1].width < found[0].width, "the count's line is the narrower");
            item.text = "12.0 GB";
            item.count = "100%";
            verify(waitForRendering(canvas));
            compare(item.width, width, "the item keeps its width as its readings change");
            compare(starts()[0], starts()[1]);
        }

        // Each stacked line draws its own icon from the shipped set at the
        // stacked size and stroke, in its own line's level colour, centred
        // in its line and the stacked gap before its value; the one icon is
        // gone, and a line with no icon name draws no icon box, its value
        // starting at the block's left edge.
        function test_stacked_lines_draw_their_own_icons_data() {
            return [
                { tag: "levels", properties: { iconName: "cpu", countIconName: "thermometer", textLevel: "warning", countLevel: "danger" },
                    icons: ["cpu", "thermometer"], colours: ["warning", "danger"] },
                { tag: "normal", properties: { iconName: "memory-stick", countIconName: "hard-drive" },
                    icons: ["memory-stick", "hard-drive"], colours: ["normal", "normal"] },
                { tag: "count-without-icon", properties: { iconName: "cpu", countLevel: "danger" },
                    icons: ["cpu"], colours: ["normal"] }
            ];
        }

        function test_stacked_lines_draw_their_own_icons(data) {
            const tone = "#123456";
            const colours = { normal: Qt.color(tone), warning: Qt.color(Theme.color.warning), danger: Qt.color(Theme.color.danger) };
            const item = createTemporaryObject(readingCase, root, Object.assign({ stacked: true, tone: tone, text: "5%", count: "41°" }, data.properties));
            verify(item !== null);
            compare(firstIcon(item).parent.visible, false, "the one icon is gone");
            const values = labels(item);
            compare(JSON.stringify(values.map(label => label.text)), JSON.stringify(["5%", "41°"]));
            const icons = lineIcons(item);
            compare(JSON.stringify(icons.map(icon => icon.name)), JSON.stringify(data.icons));
            for (const [index, icon] of icons.entries()) {
                const value = values[index];
                compare(icon.size, Theme.bar.stacked.icon);
                compare(icon.width, Theme.bar.stacked.icon);
                compare(icon.stroke, Theme.bar.stacked.iconStroke);
                compare(icon.color, colours[data.colours[index]], icon.name + " draws its line's colour");
                compare(icon.parent, value.parent, icon.name + " draws on its value's line");
                tryVerify(() => Math.abs(value.mapToItem(item, 0, 0).x - icon.mapToItem(item, icon.width, 0).x - Theme.bar.item.gap) <= 0.5, 1000,
                    icon.name + " stands the stacked gap before \"" + value.text + "\"");
                const top = icon.mapToItem(value, 0, 0).y;
                verify(top >= 0 && top + icon.height <= value.height, icon.name + " lies inside its line: top " + top);
                fuzzyCompare(top + icon.height / 2, value.height / 2, 0.5);
            }
            if (icons.length === 1)
                compare(values[1].mapToItem(item, 0, 0).x, icons[0].mapToItem(item, 0, 0).x, "a line with no icon starts at the block's left edge");
        }

        // The block holds its wider line, icon and value at its sample:
        // the item is as wide as the same item showing its samples, and
        // keeps that width as its readings change.
        function test_stacked_icons_hold_the_block_width() {
            const icons = { iconName: "cpu", countIconName: "thermometer", stacked: true };
            const held = createTemporaryObject(readingCase, root, Object.assign({ text: "3%", textSample: "100%", count: "41°", countSample: "100°" }, icons));
            const wide = createTemporaryObject(readingCase, root, Object.assign({ text: "100%", count: "100°", y: 40 }, icons));
            verify(held !== null && wide !== null);
            tryVerify(() => wide.width > wide.height, 1000, "the wide item lays out");
            tryCompare(held, "width", wide.width, 1000, "the held item is as wide as its samples shown");
            held.text = "100%";
            held.count = "100°";
            verify(waitForRendering(held));
            compare(held.width, wide.width, "the item keeps its width as its readings change");
        }

        // The stacked lines draw mixed case under a bar role that
        // uppercases, so a unit such as "MB/s" keeps its letters.
        function test_stacked_lines_keep_their_case() {
            compare(UnitTheme.override({ text: { bar: { uppercase: true } } }), "ok");
            const one = createTemporaryObject(readingCase, root, { text: "1 MB/s" });
            const item = createTemporaryObject(readingCase, root, { stacked: true, iconName: "arrow-up", countIconName: "arrow-down", text: "1 MB/s", count: "2 KB/s", y: 40 });
            verify(one !== null && item !== null);
            compare(labels(one)[0].font.capitalization, Font.AllUppercase, "the theme uppercases the bar role");
            const found = labels(item);
            compare(found.length, 2);
            for (const label of found) compare(label.font.capitalization, Font.MixedCase, "\"" + label.text + "\" keeps its case");
        }

        // One line, a spinner or one reading shown: the item keeps its one
        // mark and its lines draw no icons. One line, a caption draws once
        // and the count's label not at all.
        function test_the_one_mark_stays_data() {
            return [
                { tag: "one-line", properties: { iconName: "cpu", countIconName: "thermometer", text: "5%", count: "41°", separator: "/" }, glyph: true },
                { tag: "one-reading", properties: { iconName: "cpu", countIconName: "thermometer", text: "5%", stacked: true }, glyph: true },
                { tag: "spinner", properties: { iconName: "cpu", countIconName: "thermometer", text: "5%", count: "41°", stacked: true, spinning: true }, glyph: true },
                { tag: "one-line-caption", properties: { iconName: "cpu", countIconName: "thermometer", caption: "CPU", countCaption: "TMP", text: "5%", count: "41°", separator: "/" }, glyph: false }
            ];
        }

        function test_the_one_mark_stays(data) {
            const item = createTemporaryObject(readingCase, root, data.properties);
            verify(item !== null);
            compare(firstIcon(item).parent.visible, data.glyph);
            compare(lineIcons(item).length, 0, "no line draws an icon");
            if (data.properties.caption !== undefined)
                compare(JSON.stringify(labels(item).map(label => label.text)), JSON.stringify(["CPU", "5%", "/", "41°"]));
        }

        // Stacked with a caption, each line draws its own label at the
        // stacked size in its own line's level colour, the stacked gap
        // before its value, in place of the one caption; the labels share
        // one column as wide as the wider, so both values start at one x.
        function test_stacked_lines_draw_their_own_labels_data() {
            return [
                { tag: "levels", properties: { caption: "CPU", countCaption: "TMP", textLevel: "warning", countLevel: "danger" }, colours: ["warning", "danger"] },
                { tag: "unequal", properties: { caption: "GPU", countCaption: "T" }, colours: ["normal", "normal"] },
                { tag: "unequal-text-shorter", properties: { caption: "M", countCaption: "SWP", countLevel: "warning" }, colours: ["normal", "warning"] }
            ];
        }

        function test_stacked_lines_draw_their_own_labels(data) {
            const tone = "#123456";
            const colours = { normal: Qt.color(tone), warning: Qt.color(Theme.color.warning), danger: Qt.color(Theme.color.danger) };
            const item = createTemporaryObject(readingCase, root, Object.assign({ stacked: true, tone: tone, iconName: "cpu", text: "5%", count: "41°" }, data.properties));
            verify(item !== null);
            const found = labels(item);
            compare(JSON.stringify(found.map(label => label.text)), JSON.stringify([data.properties.caption, "5%", data.properties.countCaption, "41°"]),
                "each line draws its label and value, and no single caption stands before them");
            compare(firstIcon(item).parent.visible, false);
            compare(lineIcons(item).length, 0);
            const captions = [found[0], found[2]], values = [found[1], found[3]];
            const column = Math.max(captions[0].implicitWidth, captions[1].implicitWidth);
            for (const [index, caption] of captions.entries()) {
                compare(caption.font.pixelSize, Theme.bar.stacked.size);
                compare(caption.color, colours[data.colours[index]], "\"" + caption.text + "\" draws its line's colour");
                compare(caption.parent, values[index].parent, "\"" + caption.text + "\" draws on its value's line");
                compare(caption.width, column, "\"" + caption.text + "\" spans the label column");
            }
            tryVerify(() => Math.abs(values[0].mapToItem(item, 0, 0).x - values[1].mapToItem(item, 0, 0).x) < 0.5, 1000, "both values start at one x");
            for (const [index, value] of values.entries())
                fuzzyCompare(value.mapToItem(item, 0, 0).x - captions[index].mapToItem(item, captions[index].width, 0).x, Theme.bar.item.gap, 0.5);
            compare(captions[0].mapToItem(item, 0, 0).x, captions[1].mapToItem(item, 0, 0).x, "both labels start at one left edge");
        }

        // A spinner stays left of the stacked block: each line's box starts
        // the item gap after it, the shorter line too, with held room.
        function test_a_stacked_spinner_stands_the_item_gap_before_the_lines() {
            const item = createTemporaryObject(readingCase, root, { stacked: true, spinning: true, iconName: "cpu", countIconName: "thermometer",
                text: "3%", textSample: "100%", count: "41°", countSample: "100°" });
            verify(item !== null);
            const spinnerBox = firstIcon(item).parent;
            compare(spinnerBox.visible, true);
            const values = labels(item);
            compare(values.length, 2);
            for (const value of values)
                tryVerify(() => Math.abs(value.mapToItem(item, 0, 0).x - spinnerBox.mapToItem(item, spinnerBox.width, 0).x - item.spacing) <= 0.5, 1000,
                    "\"" + value.text + "\" starts the item gap after the spinner");
        }

        function test_one_reading_stays_one_line_data() {
            return [
                { tag: "text", properties: { text: "5%", stacked: true } },
                { tag: "count", properties: { iconName: "shield", count: "12", stacked: true } },
                { tag: "one-line", properties: { text: "5%", count: "9°", separator: "/" } }
            ];
        }

        function test_one_reading_stays_one_line(data) {
            const item = createTemporaryObject(readingCase, root, data.properties);
            verify(item !== null);
            const found = labels(item);
            verify(found.length > 0);
            const top = found[0].mapToItem(item, 0, 0).y;
            for (const label of found) {
                compare(label.font.pixelSize, Theme.text.bar.size);
                compare(label.mapToItem(item, 0, 0).y, top, "\"" + label.text + "\" draws on the one line");
            }
        }

        function test_theme_moves_the_item() {
            compare(UnitTheme.override({ bar: { item: { height: 30, paddingX: 9, icon: 20 } } }), "ok");
            compare(icon.height, 30);
            compare(counted.leftPadding, 9);
            compare(icon.width, 30);
            compare(firstIcon(icon).size, 20);
        }
    }
}
