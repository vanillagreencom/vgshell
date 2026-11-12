import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// ContentRow and NavigationRow, the two shared row parts. A content row
// takes no click, so it draws no press and shows no hand, while its
// trailing action keeps its own click, and its text starts on the content
// edge. A navigation row takes the click and shows the hand, and ends in
// its chevron, after its accessories, with no gap before the chevron
// when it has none.
Item {
    id: root
    width: 400
    height: 300

    ContentRow {
        id: content
        width: 300
        text: "Clock"
        secondary: "Show the time"
        iconName: "clock"
        trailing: [ Button { id: contentAction; size: "sm"; variant: "secondary"; text: "Add"; anchors.verticalCenter: parent.verticalCenter } ]
    }
    NavigationRow {
        id: bare
        y: 80
        width: 300
        text: "Bluetooth"
        iconName: "bluetooth"
    }
    NavigationRow {
        id: accessorised
        y: 160
        width: 300
        text: "Updates"
        iconName: "package"
        accessories: [ Badge { id: accessory; text: "2"; anchors.verticalCenter: parent.verticalCenter } ]
    }
    SignalSpy { id: actionClicks; target: contentAction; signalName: "clicked" }
    SignalSpy { id: rowClicks; target: bare; signalName: "clicked" }

    UnitCase {
        name: "rows"
        when: windowShown

        function init() { UnitTheme.reset(); actionClicks.clear(); rowClicks.clear(); }

        // Qt takes the cursor over an item from a handler of the item that
        // sets a cursor shape and is hovered; with none, the arrow shows.
        function showsHand(item, x) {
            mouseMove(item, x, item.height / 2);
            return item.data.some(child => child instanceof HoverHandler && child.cursorShape === Qt.PointingHandCursor && child.hovered);
        }

        // The rows' trailing items, in the order the row lays them out.
        function trailingOf(row) { return row.contentItem.children[2].children; }

        function test_a_content_row_takes_no_click_and_keeps_its_action() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const at = content.textStart + 1;
            compare(showsHand(content, at), false, "a content row shows no hand");
            mousePress(content, at, content.height / 2);
            compare(content.down, false, "a content row draws no press");
            mouseRelease(content, at, content.height / 2);
            mouseClick(contentAction);
            compare(actionClicks.count, 1, "the trailing action takes its own click");
        }

        function test_a_content_row_starts_its_text_on_the_content_edge() {
            const title = content.contentItem.children[1].children[0];
            compare(title.mapToItem(content, 0, 0).x, Theme.icon.size.md + Theme.listItem.iconGap);
            compare(content.textStart, Theme.icon.size.md + Theme.listItem.iconGap);
        }

        // A content row with no stacked part builds none: no stacked lines,
        // no row menu button and no menu.
        function test_a_plain_content_row_builds_no_stacked_part() {
            const found = [content];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            compare(found.filter(item => item instanceof IconButton || item instanceof Menu).length, 0, "a plain content row builds no row menu");
            compare([content.stacked, content.stackItem, content.menuButton], [false, null, null], "a plain content row builds no stacked lines");
        }

        function test_a_navigation_row_takes_the_click() {
            verify(showsHand(bare, bare.width / 2), "a navigation row shows the hand");
            mouseClick(bare);
            compare(rowClicks.count, 1);
        }

        function test_a_navigation_row_ends_in_its_chevron() {
            const items = trailingOf(accessorised);
            const chevron = items[items.length - 1];
            compare(chevron.name, "chevron-right");
            verify(chevron.visible, "the chevron shows");
            const chevronLeft = chevron.mapToItem(accessorised.contentItem, 0, 0).x;
            const accessoryRight = accessory.mapToItem(accessorised.contentItem, accessory.width, 0).x;
            compare(chevronLeft - accessoryRight, Theme.listItem.gap, "the chevron stands after the accessories");
            compare(chevron.mapToItem(accessorised.contentItem, chevron.width, 0).x, accessorised.contentItem.width, "the chevron ends the row");
        }

        function test_a_navigation_row_without_accessories_puts_no_gap_before_its_chevron() {
            const items = trailingOf(bare);
            const chevron = items[items.length - 1];
            verify(chevron.visible, "the chevron shows");
            compare(bare.contentItem.children[2].width, chevron.width, "the trailing items are the chevron alone");
        }
    }
}
