import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// MessageRow's reply-card inputs (VGS-2339): its avatar and text stand
// `messageRow.paddingX`, 6, in from each side and `messageRow.paddingY`,
// 8, from the top and bottom, marked or not; `bodyLines`
// cuts the body at that many lines and `bodyTruncated` says so, and only a
// cut body shows `cutHint`, in the text column under the body;
// `bodyComponent` draws its item in the body's place; `marked` stands the
// row on `messageRow.mark` over its whole box and moves no text. Expected
// values are worked by hand from the defaults in Tokens.js: a 24 px avatar
// and a 12 px group gap.
Item {
    id: scene
    width: 640
    height: 600

    MessageRow {
        id: row
        width: 300
        sender: "Jarvis"
        timeText: "just now"
        avatarIcon: "vgs-letter-j"
        bodyText: "A short answer."
        cutHint: "Click to read the full answer"
    }
    MessageRow {
        id: slotted
        y: 300
        width: 300
        sender: "Jarvis"
        bodyComponent: Component { Rectangle { objectName: "slotItem"; width: parent ? parent.width : 0; height: 40 } }
    }

    TestCase {
        name: "message_row"
        when: windowShown

        function init() {
            UnitTheme.reset();
            row.bodyLines = 0;
            row.marked = false;
            row.bodyText = "A short answer.";
        }

        function allChildren(item) {
            let found = [];
            for (const child of item.children) found = found.concat([child], allChildren(child));
            return found;
        }
        function labelOf(item, text) {
            return allChildren(item).find(child => child.text === text && child.visible);
        }
        function plateOf(item) {
            return item.children.find(child => child.color !== undefined && child.anchors !== undefined && child.anchors.fill === item);
        }

        function test_the_avatar_and_text_stand_in_from_each_side() {
            const avatar = allChildren(row).find(child => child.people !== undefined);
            compare(avatar.x, 6);
            const body = labelOf(row, "A short answer.");
            compare(body.mapToItem(row, 0, 0).x, 6 + 24 + 12);
            compare(body.mapToItem(row, 0, 0).x + body.width, 300 - 6);
        }

        function test_the_avatar_and_text_stand_in_from_top_and_bottom() {
            const avatar = allChildren(row).find(child => child.people !== undefined);
            const body = labelOf(row, "A short answer.");
            compare(avatar.y, 8);
            compare(row.height - body.mapToItem(row, 0, body.height).y, 8, "the body ends paddingY above the row's bottom");
            compare(UnitTheme.override({ messageRow: { paddingY: 12 } }), "ok");
            compare(avatar.y, 12, "the top padding is the messageRow token's");
            compare(row.height - body.mapToItem(row, 0, body.height).y, 12, "the bottom padding is the messageRow token's");
        }

        function test_a_cut_body_says_so_under_it() {
            row.bodyText = Array(40).fill("word").join(" ");
            row.bodyLines = 2;
            tryCompare(row, "bodyTruncated", true);
            const body = allChildren(row).find(child => child.text === row.bodyText);
            compare(body.lineCount, 2);
            const hint = labelOf(row, "Click to read the full answer");
            verify(hint !== undefined, "the cut body shows its hint");
            compare(hint.mapToItem(row, 0, 0).x, body.mapToItem(row, 0, 0).x, "the hint stands in the body's column");
            verify(hint.mapToItem(row, 0, 0).y >= body.mapToItem(row, 0, body.height).y, "the hint stands under the body");
        }

        function test_a_whole_body_shows_no_hint() {
            row.bodyLines = 4;
            compare(row.bodyTruncated, false);
            compare(labelOf(row, "Click to read the full answer"), undefined);
            row.bodyLines = 0;
            row.bodyText = Array(40).fill("word").join(" ");
            compare(row.bodyTruncated, false, "no cap keeps every line");
        }

        function test_a_body_component_draws_in_the_bodys_place() {
            const item = allChildren(slotted).find(child => child.objectName === "slotItem");
            verify(item !== undefined, "the row builds its body item");
            compare(item.mapToItem(slotted, 0, 0).x, 6 + 24 + 12);
            verify(slotted.implicitHeight >= 40, "the row's height holds its body item");
        }

        function test_a_mark_covers_the_row_and_moves_no_text() {
            const body = labelOf(row, "A short answer.");
            const before = body.mapToItem(row, 0, 0);
            const plate = plateOf(row);
            compare(plate.visible, false, "an unmarked row draws no plate");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            row.marked = true;
            tryCompare(plate, "opacity", 1);
            compare(String(plate.color), String(Qt.color(Theme.listItem.selected)));
            compare([plate.x, plate.y, plate.width, plate.height], [0, 0, row.width, row.height], "the plate is the row's whole box");
            const after = body.mapToItem(row, 0, 0);
            compare([after.x, after.y], [before.x, before.y], "the mark moves no text");
            row.marked = false;
            tryCompare(plate, "opacity", 0);
        }
    }
}
