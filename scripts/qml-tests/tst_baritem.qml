import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// BarItem: every bar widget's one item. It is `bar.item.height` tall and
// never narrower; its content sits `bar.item.paddingX` in; the icon is
// `bar.item.icon` wide at full opacity; a count draws in the bar role in
// the item's tone; `active` fills it with `bar.active`; hover and press
// fill it with their own tokens; a click emits `clicked`.
Item {
    id: root
    width: 300
    height: 160

    BarItem { id: icon; iconName: "settings"; label: "Settings"; onClicked: root.clicks += 1 }
    BarItem { id: counted; iconName: "shield"; count: "12"; tone: "#ff0000"; y: 40 }
    BarItem { id: pill; text: "1"; active: true; y: 80 }
    BarItem { id: spinner; iconName: "refresh-cw"; spinning: true; y: 120 }
    BarItem { id: tooltipItem; iconName: "settings"; label: "Settings"; tooltip: "Open settings"; tooltipDetails: ["Pinned in the bar"]; x: 80 }
    BarItem { id: reserved; text: "5%"; reservedText: "100%"; count: "9°"; reservedCount: "100°"; x: 150 }
    property int clicks: 0
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

        function test_reserved_text_and_count_keep_the_width() {
            reserved.text = "5%"; reserved.count = "9°";
            verify(waitForRendering(reserved));
            const width = reserved.width;
            reserved.text = "100%";
            verify(waitForRendering(reserved));
            compare(reserved.width, width);
            reserved.count = "100°";
            verify(waitForRendering(reserved));
            compare(reserved.width, width);
        }

        function test_reservations_follow_the_drawn_reading() {
            reserved.iconName = "cpu"; reserved.text = "5%"; reserved.count = "/9°"; reserved.compactCount = true;
            const found = labels(reserved), glyph = firstIcon(reserved);
            tryVerify(() => Math.abs(found[0].mapToItem(reserved, 0, 0).x - glyph.mapToItem(reserved, glyph.width, 0).x - Theme.bar.item.iconGap) <= 0.5, 1000, "the drawn reading follows the icon after layout");
            fuzzyCompare(found[0].mapToItem(reserved, 0, 0).x - glyph.mapToItem(reserved, glyph.width, 0).x, Theme.bar.item.iconGap, 0.5);
            fuzzyCompare(found[1].mapToItem(reserved, 0, 0).x, found[0].mapToItem(reserved, found[0].width, 0).x, 0.5);
            verify(found[1].mapToItem(reserved, found[1].width, 0).x < reserved.width - reserved.rightPadding);
            reserved.iconName = ""; reserved.compactCount = false;
        }

        function test_text_and_count_take_separate_tones() {
            reserved.text = "5%"; reserved.count = "9°";
            reserved.tone = "#ff0000";
            reserved.textTone = "#0000ff";
            reserved.countTone = "#00ff00";
            compare(String(labels(reserved)[0].color), "#0000ff");
            compare(String(labels(reserved)[1].color), "#00ff00");
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
