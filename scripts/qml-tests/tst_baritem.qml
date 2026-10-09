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
// held room; `active`
// fills it with `bar.active`;
// hover and press fill it with their own tokens; a click emits `clicked`.
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
        // The blank between the icon's or caption's ink and the first
        // value's ink.
        function markGap(img, item) {
            const glyph = firstIcon(item);
            const mark = glyph.parent.visible ? glyph : labels(item)[0];
            const value = labels(item).find(label => label.text === item.text);
            const markInk = inkRight(img, mark), valueInk = inkLeft(img, value);
            verify(markInk >= 0 && valueInk >= 0, "the mark and \"" + item.text + "\" draw");
            return valueInk - (markInk + 1);
        }

        // A short and the widest value held at the same sample: the held
        // room sits before the icon or caption, so the blank between it and
        // the value is the one the same item with no held room draws.
        function test_the_mark_stays_beside_its_value_data() {
            return [
                { tag: "short", held: { iconName: "cpu", text: "9%", textSample: "100%" } },
                { tag: "widest", held: { iconName: "cpu", text: "100%", textSample: "100%" } },
                { tag: "short-count", held: { iconName: "cpu", text: "9%", textSample: "100%", count: "9°", countSample: "100°", separator: "/" } },
                { tag: "short-caption", held: { caption: "RAM", text: "1.0 GB", textSample: "12.0 GB", count: "9%", countSample: "100%" } }
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
            const heldGap = markGap(img, held), bareGap = markGap(img, bare);
            verify(Math.abs(heldGap - bareGap) <= 1, "the held item keeps its mark beside its value: held " + heldGap + ", bare " + bareGap);
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

        function test_theme_moves_the_item() {
            compare(UnitTheme.override({ bar: { item: { height: 30, paddingX: 9, icon: 20 } } }), "ok");
            compare(icon.height, 30);
            compare(counted.leftPadding, 9);
            compare(icon.width, 30);
            compare(firstIcon(icon).size, 20);
        }
    }
}
