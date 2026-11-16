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
// when it has none. A row that takes its stacked lines while hidden lays
// them out, once it shows, as a row that took them while shown. A stacked
// row with a secondary line keeps its row menu and trailing controls on
// its name's line.
Item {
    id: root
    width: 400
    height: 560

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
    ContentRow {
        id: stackedShown
        y: 240
        width: 300
        text: "Backup"
        iconName: "clock"
        status: "Done"
        statusTone: "success"
        detail: "Next Mon 09:00"
    }
    Item {
        id: hider
        y: 360
        width: 300
        ContentRow { id: stackedHidden; width: 300; text: "Backup"; iconName: "clock" }
    }
    ContentRow {
        id: stackedSecondary
        y: 450
        width: 300
        text: "Backup"
        secondary: "Every 10 minutes"
        iconName: "clock"
        status: "Done"
        statusTone: "success"
        menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]
        trailing: [ Switch { id: secondarySwitch; size: "sm"; anchors.verticalCenter: parent.verticalCenter } ]
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

        function test_a_row_stacked_while_hidden_lays_out_once_shown() {
            hider.visible = false;
            stackedHidden.status = "Done";
            stackedHidden.statusTone = "success";
            stackedHidden.detail = "Next Mon 09:00";
            tryVerify(() => stackedHidden.stacked && !stackedHidden.settlePending, 1000, "the hidden row took its stacked lines");
            hider.visible = true;
            const layout = row => JSON.stringify([row.topPadding, row.bottomPadding, row.height]);
            tryVerify(() => layout(stackedHidden) === layout(stackedShown), 1000,
                "the row lays out as one stacked while shown: " + layout(stackedHidden) + " against " + layout(stackedShown));
        }

        function test_a_stacked_rows_menu_and_controls_stand_on_its_names_line() {
            tryVerify(() => stackedSecondary.menuButton !== null && !stackedSecondary.settlePending, 1000, "the row built its menu and settled");
            const title = stackedSecondary.contentItem.children[1].children[0];
            const centre = item => item.mapToItem(stackedSecondary, 0, item.height / 2).y;
            fuzzyCompare(centre(stackedSecondary.menuButton), centre(title), 1, "the row menu centres on the name's line");
            fuzzyCompare(centre(secondarySwitch), centre(title), 1, "the trailing switch centres on the name's line");
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
