import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// The spacing rhythm, read from drawn components: Button, TextField,
// Select and SegmentedControl stand `size.control.md` tall with their text
// `control.paddingX` from the edge; ListItem and MenuItem start their
// content `row.paddingX` in; Field starts at `field.paddingX`, zero by
// default so a container owns its edge. Controls share `control.gap`;
// ListItem owns its larger icon gap and Badge its smaller chip gap. A theme that moves the shared token
// moves every component that follows it. A group space, `stack.group`,
// comes before a group: a button row after text, the row after a row's
// lines, hint or error line, and a section's first row after its
// description.
Item {
    id: root
    width: 400
    height: 1700

    Button { id: button; text: "Publish"; iconName: "check" }
    TextField { id: input; width: 200; y: 40 }
    TextField { id: iconed; leadingIcon: "search"; width: 200; y: 80 }
    Select { id: select; width: 200; y: 120; model: ["one", "two"] }
    SegmentedControl { id: segmented; y: 160; model: ["Day", "Week"] }
    ListItem { id: item; text: "Plugin updates"; iconName: "package"; width: 300; y: 200 }
    MenuItem { id: entry; text: "Open"; iconName: "folder"; width: 200; y: 240 }
    Field { id: field; label: "Name"; width: 300; y: 280; TextField { width: parent.width } }
    Badge { id: badge; text: "new"; iconName: "check"; y: 340 }
    Checkbox { id: check; text: "Pin"; y: 470 }
    Kbd { id: key; text: "Ctrl"; x: 300; y: 340 }
    ListItem { id: twoLine; text: "Two lines"; secondary: "detail"; width: 300; y: 500 }
    CodeLine { id: code; text: "vgshell plugin enable acme.weather"; width: 300; y: 560 }
    Card { id: card; x: 320; y: 560; width: 300; Item { width: 10; height: 100 } }
    Section {
        id: section
        title: "Section"
        y: 620
        width: 300
        Rectangle { width: 10; height: 10 }
        Rectangle { width: 10; height: 10 }
    }
    Section {
        id: describedSection
        title: "Described"
        description: "A short description"
        y: 680
        width: 300
        Rectangle { width: 10; height: 10 }
    }
    Disclosure {
        id: disclosure
        text: "System"
        iconName: "package"
        expanded: true
        width: 300
        y: 760
        Rectangle { id: disclosed; width: parent.width; height: 10 }
    }
    Field { id: inlineField; label: "Version"; inline: true; width: 300; y: 840; Label { role: "item"; text: "0.1.0" } }
    Field { id: inlineSwitchSm; label: "Switch sm"; hint: "Hint"; inline: true; width: 300; y: 880; Switch { id: switchSm; size: "sm"; checked: true } }
    Field { id: inlineSwitchMd; label: "Switch md"; hint: "Hint"; inline: true; width: 300; y: 920; Switch { id: switchMd; checked: true } }
    Field { id: inlineSegmented; label: "Segments"; hint: "Hint"; inline: true; width: 300; y: 960; SegmentedControl { id: inlineSeg; width: parent.width; model: ["One", "Two"] } }
    Field { id: inlineTextField; label: "Text"; hint: "Hint"; inline: true; width: 300; y: 1000; TextField { id: inlineTextInput; width: parent.width; text: "abc" } }
    Column {
        id: fieldRows
        y: 1060
        width: 300
        spacing: Theme.stack.row
        Field { id: hintedRow; label: "Interval"; hint: "How often it checks"; inline: true; width: parent.width; Switch { size: "sm" } }
        Field { id: afterHint; label: "View"; inline: true; width: parent.width; Switch { size: "sm" } }
        Field { id: plainRow; label: "Plain"; inline: true; width: parent.width; Switch { size: "sm" } }
        Field { id: lastHinted; label: "Last"; hint: "Ends the column"; inline: true; width: parent.width; Switch { size: "sm" } }
    }
    GroupList {
        id: hintedGroups
        y: 1240
        width: 300
        Field { id: groupedHinted; label: "Grouped"; hint: "A hint"; inline: true; width: parent.width; Switch { size: "sm" } }
        Field { id: groupedNext; label: "Next"; inline: true; width: parent.width; Switch { size: "sm" } }
    }
    Column {
        id: linedRows
        y: 1420
        width: 300
        spacing: Theme.stack.row
        Field { id: linedRow; label: "Model"; lines: ["Choose a model below.", "Then add its key."]; inline: true; width: parent.width; Badge { text: "To do" } }
        Field { id: afterLines; label: "Voice"; inline: true; width: parent.width; Badge { text: "Done" } }
        Field { id: linedHinted; label: "Browser"; lines: ["One line"]; hint: "Set up the browser."; inline: true; width: parent.width; Badge { text: "Optional" } }
        Field { id: afterBoth; label: "Input"; inline: true; width: parent.width; Badge { text: "Optional" } }
    }
    Section {
        id: blockSection
        title: "Setup"
        rowSpacing: Theme.stack.group
        y: 1320
        width: 300
        Label { id: stateText; role: "hint"; text: "Ready"; width: parent.width }
        Row { id: buttonRow; Button { text: "Set up" } }
    }
    Text {
        id: clearingProbeText
        text: "A message long enough to wrap after the inset grows and makes the line narrower."
        width: clearingProbe.width - 2 * clearingProbe.inset
        wrapMode: Text.WordWrap
    }
    ClearingInset {
        id: clearingProbe
        pad: 4
        radius: 4096
        width: 120
        height: clearingProbeText.implicitHeight + 8
        step: 4
        top: 4
    }

    TestCase {
        name: "spacing"
        when: windowShown

        function init() { UnitTheme.reset(); }

        // The gap between the first two children of a row: an icon and
        // the text after it.
        function gapOf(row) { return row.children[1].x - (row.children[0].x + row.children[0].width); }
        function badgeGap(item) {
            const icon = item.children.find(child => child.name === item.iconName);
            const label = item.children.find(child => child.role === "label");
            return label.x - (icon.x + icon.width);
        }
        function hintGap(field, control) {
            const hint = field.children[2].children[0];
            return hint.mapToItem(field, 0, 0).y - control.mapToItem(field, 0, control.height).y;
        }

        function segment(index) { return segmented.children[0].children[index]; }

        // A positioner lays its children out on the next polish, so a
        // position is waited for rather than read at once.
        function same(read, want, what) { tryVerify(() => read() === want, 1000, what + ": got " + read() + ", want " + want); }
        function close(read, want, what) { tryVerify(() => Math.abs(read() - want) <= 0.01, 1000, what + ": got " + read() + ", want " + want); }

        function checkRhythm() {
            const height = Theme.size.control.md;
            const pad = Theme.control.paddingX;
            same(() => button.height, height, "button height");
            same(() => input.height, height, "text field height");
            same(() => select.height, height, "select height");
            same(() => segmented.height, height, "segmented height");
            same(() => button.leftPadding, pad, "button padding");
            same(() => button.contentItem.x, pad, "button text x");
            same(() => input.leftPadding, Theme.textField.paddingX, "text field padding");
            same(() => select.contentItem.x, Theme.textField.paddingX, "select text x");
            same(() => segment(0).contentItem.x, pad, "segment text x");
            same(() => segment(0).width - segment(0).contentItem.x - segment(0).contentItem.width, pad, "segment right padding");

            const row = Theme.row.paddingX;
            same(() => item.contentItem.x, row, "list item content x");
            same(() => entry.contentItem.x, row, "menu item content x");
            const fieldPad = Theme.field.paddingX;
            same(() => field.children[0].x, fieldPad, "field label x");
            same(() => field.children[1].x, fieldPad, "field control row x");
            same(() => field.children[1].width, field.width - 2 * fieldPad, "field control row width");

            const gap = Theme.control.gap;
            same(() => gapOf(button.contentItem), gap, "button icon gap");
            same(() => iconed.leftPadding, Theme.textField.paddingX + Theme.icon.size.md + gap, "text field icon gap");
            same(() => gapOf(item.contentItem), Theme.listItem.iconGap, "list item icon gap");
            same(() => gapOf(entry.contentItem), gap, "menu item icon gap");
            same(() => badgeGap(badge), Theme.badge.gap, "badge icon gap");
            same(() => badge.implicitWidth, 2 * badge.sidePadding + badge.children.find(child => child.role === "label").opticalWidth + Theme.icon.size.xs + Theme.badge.gap + Theme.badge.paddingEnd, "badge optical width");
            same(() => check.contentItem.leftPadding - check.indicator.width, gap, "checkbox gap");
        }

        function test_components_share_the_rhythm() {
            compare(Theme.control.paddingX, 12);
            compare(Theme.control.gap, 8);
            compare(Theme.badge.gap, 4);
            compare(Theme.badge.paddingEnd, 3);
            compare(Theme.row.paddingX, 12);
            compare(Theme.field.paddingX, 0);
            compare(Theme.listItem.iconGap, 12);
            checkRhythm();
        }

        function test_one_token_moves_every_component() {
            compare(UnitTheme.override({ size: { control: { md: 34 } }, control: { paddingX: 13, gap: 3 }, row: { paddingX: 20 }, field: { paddingX: 5 }, listItem: { iconGap: 16 } }), "ok");
            compare(Theme.control.paddingX, 13);
            compare(Theme.row.paddingX, 20);
            compare(Theme.field.paddingX, 5);
            compare(Theme.listItem.iconGap, 16);
            checkRhythm();
        }

        // Under a pill theme with small pads, each one-line component's side
        // padding grows past its pad until its content clears the round
        // end, and never past the end's centre and a step.
        function test_rounded_components_clear_their_corners() {
            compare(UnitTheme.override({ radius: { sm: 4096 }, badge: { size: { sm: { paddingX: 2 } } }, kbd: { paddingX: 2 }, listItem: { paddingX: 4 }, menu: { item: { paddingX: 4, radius: 4096 } }, textField: { paddingX: 4 }, segmented: { paddingX: 4, radius: 4096 }, codeLine: { padding: 2 } }), "ok");
            const cases = [
                ["badge", () => badge.children.find(child => child.role === "label").x - (badge.iconName !== "" ? Theme.icon.size.xs + Theme.badge.gap : 0), 2, badge.height],
                ["kbd", () => key.sidePadding, 2, key.height],
                ["two-line list item", () => twoLine.leftPadding, 4, twoLine.height],
                ["menu item", () => entry.leftPadding, 4, entry.height],
                ["text field", () => input.leftPadding, 4, input.height],
                ["select", () => select.leftPadding, 4, select.height],
                ["segment", () => segment(0).leftPadding, 4, segment(0).height],
                ["code line", () => code.children.find(child => child.role === "code").x, 2, code.height]
            ];
            for (const [what, read, pad, height] of cases) {
                tryVerify(() => read() > pad, 1000, what + " padding " + read() + " grew past its pad " + pad);
                verify(read() <= height / 2 + Theme.space.xs, what + " padding " + read() + " stays within its round end");
            }
        }

        // A row names where its text starts: the pad, 12, the icon, 16, and
        // the icon gap, 12, for a row with an icon, and the pad alone
        // without one; the title is drawn there.
        function test_a_row_names_where_its_text_starts() {
            compare(item.textStart, 40);
            compare(item.leftPadding + item.contentItem.children[1].x, 40);
            compare(twoLine.textStart, 12);
            compare(twoLine.leftPadding + twoLine.contentItem.children[1].x, 12);
        }

        // A section's heading sits on the content edge and its rows take
        // its row spacing; a disclosure's content starts at the row's text
        // column; an inline field uses the same row height for read-only text.
        function test_section_disclosure_and_inline_field() {
            compare(section.children[0].leftPadding, 0);
            const rows = section.children[1];
            compare(rows.spacing, Theme.stack.row);
            section.rowSpacing = Theme.stack.group;
            compare(rows.spacing, Theme.stack.group);
            section.rowSpacing = Theme.stack.row;
            const header = describedSection.children[0];
            const first = describedSection.children[1].children[0];
            const description = header.children[1];
            compare(first.mapToItem(describedSection, 0, 0).y - description.mapToItem(describedSection, 0, description.height).y, Theme.stack.group, "a section's first row is a group space below its description");
            compare(first.mapToItem(describedSection, 0, 0).y - header.mapToItem(describedSection, 0, header.height).y, 0);
            compare(section.children[1].children[0].mapToItem(section, 0, 0).y - section.children[0].mapToItem(section, 0, section.children[0].height).y, 0);
            const title = section.children[0].children[0];
            compare(section.children[1].children[0].mapToItem(section, 0, 0).y - title.mapToItem(section, 0, title.height).y, Theme.space.md, "a section without a description keeps its heading's space");
            const inset = Theme.listItem.paddingX + Theme.icon.size.md + Theme.listItem.iconGap;
            compare(disclosed.parent.x, inset);
            compare(disclosed.width, disclosure.width - inset - Theme.listItem.paddingX);
            compare(inlineField.children[1].height, Theme.row.height);
            compare(inlineField.height, Theme.row.height);
        }

        function test_inline_field_hints_start_under_the_control() {
            const rows = [[inlineSwitchSm, switchSm], [inlineSwitchMd, switchMd], [inlineSegmented, inlineSeg], [inlineTextField, inlineTextInput]];
            for (const row of rows) {
                compare(row[0].children[1].height, Theme.row.height);
                compare(hintGap(row[0], row[1]), Theme.field.gap);
            }
        }

        // The bottom of a field's hint or error line in `item`'s frame.
        function lineBottom(field, item) {
            const line = field.children[2].children[0];
            return line.mapToItem(item, 0, line.height).y;
        }
        function topIn(row, item) { return row.mapToItem(item, 0, 0).y; }

        // A row with a hint or error line under it is followed by a group
        // space; a row without one keeps the column's spacing; the last
        // row and a row outside a positioner end at their line, so the
        // space after a section or a page stays its own; a group list's
        // gap already is a group space.
        function test_a_group_space_follows_a_row_with_sub_text() {
            same(() => topIn(afterHint, fieldRows) - lineBottom(hintedRow, fieldRows), Theme.stack.group, "the row after a hint");
            same(() => topIn(plainRow, fieldRows) - topIn(afterHint, fieldRows), Theme.row.height + Theme.stack.row, "the row after a row without sub-text");
            afterHint.error = "Refused";
            same(() => topIn(plainRow, fieldRows) - lineBottom(afterHint, fieldRows), Theme.stack.group, "the row after an error");
            afterHint.error = "";
            same(() => fieldRows.height, lineBottom(lastHinted, fieldRows), "the column's end after its last hinted row");
            same(() => inlineSwitchSm.height, lineBottom(inlineSwitchSm, inlineSwitchSm), "a hinted field outside a positioner ends at its hint");
            same(() => topIn(groupedNext, hintedGroups) - lineBottom(groupedHinted, hintedGroups), Theme.groupList.gap, "a group list's gap after a hint");
        }

        // A row's lines sit under its value from the value column, its hint
        // `field.gap` under them, and the next row starts a group space
        // under the last of them.
        function test_a_group_space_follows_a_row_with_lines() {
            const lines = field => field.children[2].children[1].children.filter(child => child.role === "value");
            const bottom = (item, within) => item.mapToItem(within, 0, item.height).y;
            same(() => lines(linedRow).length, 2, "a line for each of lines");
            same(() => lines(linedRow).every(line => line.visible), true, "the lines show");
            same(() => lines(linedRow)[0].mapToItem(linedRow, 0, 0).x, linedRow.valueX, "the lines start on the value column");
            same(() => topIn(afterLines, linedRows) - bottom(lines(linedRow)[1], linedRows), Theme.stack.group, "the row after a row's lines");
            same(() => lines(linedHinted).length, 1, "one line");
            const hint = linedHinted.children[2].children[0];
            same(() => hint.mapToItem(linedRows, 0, 0).y - bottom(lines(linedHinted)[0], linedRows), Theme.field.gap, "the hint under the lines");
            same(() => topIn(afterBoth, linedRows) - lineBottom(linedHinted, linedRows), Theme.stack.group, "the row after lines and a hint");
        }

        // A section of blocks, such as a state over a button row, sets its
        // rows a group space apart.
        function test_a_group_space_comes_before_a_button_row() {
            same(() => topIn(buttonRow, blockSection) - stateText.mapToItem(blockSection, 0, stateText.height).y, Theme.stack.group, "the button row after text");
        }

        // The least whole inset from the pad whose content corner, `top`
        // down, keeps `step` inside a corner circle of radius `corner`.
        function leastClearing(pad, corner, top, step) {
            for (let x = pad; x < corner + step; x++)
                if (corner - Math.hypot(Math.max(0, corner - x), Math.max(0, corner - top)) >= step) return x;
            return Math.ceil(corner + step);
        }

        // A card's content moves in from a rounded corner until its own
        // corner, the pad down, stands the corner step inside the curve.
        function test_card_content_clears_its_corner_by_the_step() {
            compare(UnitTheme.override({ card: { radius: 48 } }), "ok");
            const pad = Theme.card.padding;
            tryVerify(() => card.contentInset > pad, 1000, "card rounded inset grew");
            const inset = leastClearing(pad, Math.min(Theme.card.radius, card.width / 2, card.height / 2), pad, Theme.space.xs);
            verify(inset > pad && inset < Theme.card.radius, "the card's content clears inside the curve, not past the whole corner: " + inset);
            close(() => card.contentInset, inset, "card rounded inset");
        }

        function test_clearing_inset_settles_after_wrapped_height_grows() {
            clearingProbe.reset();
            tryVerify(() => clearingProbe.inset > clearingProbe.pad, 1000, "clearing inset grew");
            close(() => clearingProbe.inset, Math.ceil(Inset.clearing(clearingProbe.pad, clearingProbe.radius, clearingProbe.width, clearingProbe.height, clearingProbe.step, clearingProbe.top)), "clearing inset fixed point");
        }
    }
}
