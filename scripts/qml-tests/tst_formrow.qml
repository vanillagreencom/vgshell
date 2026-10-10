import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// FormRow: the label column is `field.labelWidth` wide and the control
// starts `field.labelGap` after it and ends on the row's end edge; the row
// box is `row.height` tall unless its control is taller; the label sits by
// capital height and the control by its box; a message draws as hint text
// under the value column, `field.gap` below the row box and wrapped to the
// column, in its tone's colour, or in the role `warningRole` names, grows
// the row by the gap and its own
// height, and moves neither the label nor the control; an action draws on
// the message's line, on the row's end edge, the message wrapping before
// it, only while the row has a message and the action shows, at the
// message's height so it moves no row below it, and goes on a
// line of its own under the message where it would leave the message less
// than the label column's width; without a label
// column the control takes the full width at its own height; the smoke's
// `fieldRow` hook names the row. A row with a message is followed by a group
// space, `stack.group`, unless it is the last row of its column; the rows
// of the first column sit 0 apart, so each with a message there grows by
// the group space under its message.
Item {
    id: root
    width: 480
    height: 900

    Column {
        width: 420
        FormRow { id: plain; width: parent.width; label: "Clock"; Switch { id: toggle; size: "sm" } }
        FormRow { id: filled; width: parent.width; label: "Format"; Select { id: choice; width: parent.width; model: ["HH:mm", "hh:mm ap"] } }
        FormRow { id: tall; width: parent.width; label: "Preview"; Rectangle { id: block; width: 40; height: Theme.row.height + 24; color: "transparent" } }
        FormRow { id: warned; width: parent.width; label: "Speed"; warning: "Overridden"; Slider { id: speed; width: parent.width; from: 0; to: 1; value: 0.5 } }
        FormRow { id: wrapped; width: parent.width; label: "Scroll"; warning: "A message too long for one line of the value column wraps inside it and never runs under the label column"; Switch { size: "sm" } }
        FormRow { id: bare; width: parent.width; label: "Hidden"; labelColumn: false; Rectangle { id: thin; width: parent.width; height: 8; color: "transparent" } }
        FormRow { id: bareWarned; width: parent.width; labelColumn: false; warning: "Refused"; Rectangle { id: thinWarned; width: parent.width; height: 8; color: "transparent" } }
        FormRow { id: acted; width: parent.width; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: undo; width: 90; height: 30; color: "transparent" } Switch { id: actedToggle; size: "sm" } }
        FormRow { id: actedQuiet; width: parent.width; label: "Speed"; action: Rectangle { id: quietUndo; width: 90; height: 30; color: "transparent" } Switch { size: "sm" } }
        FormRow { id: cramped; width: 2 * Theme.field.labelWidth + Theme.field.labelGap + Theme.stack.inline + crampedUndo.width - 1; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: crampedUndo; width: 90; height: 30; color: "transparent" } Switch { size: "sm" } }
        FormRow { id: roomy; width: cramped.width + 1; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: roomyUndo; width: 90; height: 30; color: "transparent" } Switch { size: "sm" } }
        Badge { id: chip; text: "Chip" }
    }

    Column {
        id: spaced
        y: 640
        width: 420
        spacing: Theme.stack.row
        FormRow { id: warnedFirst; width: parent.width; label: "Speed"; warning: "Overridden"; Switch { size: "sm" } }
        FormRow { id: afterWarning; width: parent.width; label: "Scroll"; Switch { size: "sm" } }
        FormRow { id: plainNext; width: parent.width; label: "Tap"; Switch { size: "sm" } }
        FormRow { id: warnedLast; width: parent.width; label: "Click"; warning: "Overridden"; Switch { size: "sm" } }
    }

    FormRow { id: roled; y: 840; width: 420; label: "Speed"; warning: "Overridden"; warningRole: "tooltip"; Switch { size: "sm" } }
    FormRow {
        id: explainedLabel
        y: 860
        width: 420
        label: "Shortcut"
        labelTooltip: "Change its keyboard shortcut."
        Label { role: "value"; text: "Available" }
    }

    TestCase {
        name: "formrow"
        when: windowShown

        function labelOf(row) { return row.children[0]; }
        function messageOf(row) { return row.children.find(child => child.role === "hint"); }
        function xIn(item, row) { return item.mapToItem(row, 0, 0).x; }
        function centreIn(item, row) { return item.mapToItem(row, 0, item.height / 2).y; }
        function typesUnder(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children) found.push(child);
            return found.map(child => String(child).split("_QMLTYPE_")[0]);
        }

        function init() { UnitTheme.reset(); }

        // The room a row with a message takes under it in the first
        // column, whose spacing is 0.
        function room() { return Theme.stack.group; }
        function messageBottom(row, item) {
            const message = messageOf(row);
            return message.mapToItem(item, 0, message.height).y;
        }

        function test_label_focus_uses_qt_keyboard_state() {
            const label = labelOf(explainedLabel);
            const control = label.children.find(child => child.visualFocus !== undefined);
            const ring = label.children.find(child => String(child).indexOf("FocusRing") === 0);
            control.forceActiveFocus(Qt.OtherFocusReason);
            compare(control.activeFocus, true);
            compare(control.Accessible.name, explainedLabel.label);
            compare(control.Accessible.role, Accessible.StaticText);
            compare(ring.visible, false);
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Backtab);
            compare(control.activeFocus, true);
            compare(ring.visible, true);
        }

        function test_a_row_is_the_row_height_with_a_label_column() {
            for (const row of [plain, filled])
                compare(row.height, Theme.row.height);
            compare(plain.valueX, Theme.field.labelWidth + Theme.field.labelGap);
            compare(xIn(toggle, plain), plain.valueX);
            compare(xIn(choice, filled), filled.valueX);
            compare(xIn(choice, filled) + choice.width, filled.width, "the control ends on the row's end edge");
            compare(labelOf(plain).width, Theme.field.labelWidth);
            compare(labelOf(plain).y, labelOf(plain).topForCapCenter(plain.height), "the label sits by capital height");
            fuzzyCompare(centreIn(toggle, plain), plain.height / 2, 1);
            verify(!messageOf(plain).visible, "a row without a message draws one");
        }

        function test_a_message_draws_in_the_role_the_row_names() {
            const message = roled.children.find(child => child.role === "tooltip");
            verify(message !== undefined && message.visible, "the row draws no message in the role it names");
            verify(messageOf(roled) === undefined, "the row draws a hint message too");
        }

        function test_a_taller_control_grows_the_row() {
            compare(tall.height, block.height);
            compare(block.mapToItem(tall, 0, 0).y, 0);
        }

        function test_a_message_sits_under_the_value_column() {
            const message = messageOf(warned);
            verify(message.visible, "the row draws no message");
            compare(message.role, "hint");
            compare(xIn(message, warned), warned.valueX);
            compare(xIn(message, warned) + message.width, warned.width);
            compare(message.y, Theme.row.height + Theme.field.gap, "the message starts the field gap below the row box");
            verify(message.height > 0);
            compare(warned.implicitHeight, Theme.row.height + Theme.field.gap + message.height + room());
            compare(warned.height, warned.implicitHeight);
            compare(typesUnder(chip)[0], "Badge", "the reader names no chip");
            verify(typesUnder(warned).indexOf("Badge") === -1, "the row draws a chip");
        }

        function test_a_message_takes_no_room_from_the_control() {
            const placed = () => [xIn(speed, warned), speed.width, centreIn(speed, warned), labelOf(warned).y];
            const withMessage = placed();
            compare(withMessage[0], warned.valueX);
            compare(withMessage[1], warned.width - warned.valueX);
            compare(withMessage[0], xIn(choice, filled), "a message moves the control off a plain row's column");
            compare(withMessage[1], choice.width, "a message narrows the control");
            fuzzyCompare(withMessage[2], Theme.row.height / 2, 1, "the control leaves the row box's centre");
            compare(withMessage[3], labelOf(warned).topForCapCenter(Theme.row.height), "the label leaves the row box's centre");
            warned.warning = "";
            compare(warned.height, Theme.row.height);
            verify(!messageOf(warned).visible, "an empty message still draws");
            compare(placed(), withMessage);
            warned.warning = "Overridden";
        }

        function test_an_action_sits_on_the_message_line_at_the_end_edge() {
            const message = messageOf(acted);
            verify(undo.height > message.height, "the action is no taller than the message");
            compare(undo.mapToItem(acted, 0, 0).x + undo.width, acted.width, "the action ends on the row's end edge");
            compare(xIn(message, acted), acted.valueX);
            compare(message.width, acted.width - acted.valueX - undo.width - Theme.stack.inline, "the message runs under the action");
            compare(acted.height, Theme.row.height + Theme.field.gap + message.height + room(), "the row grows for a taller action");
            compare(message.y, Theme.row.height + Theme.field.gap);
            fuzzyCompare(centreIn(message, acted), centreIn(undo, acted), 1, "the message leaves the action's line");
            fuzzyCompare(centreIn(actedToggle, acted), Theme.row.height / 2, 1, "the control leaves the row box's centre");
        }

        // The value column of `cramped` is one pixel short of the label
        // column's width beside the action; `roomy` has that pixel.
        function test_an_action_with_no_room_beside_the_message_goes_under_it() {
            const message = messageOf(cramped);
            compare(message.width, cramped.width - cramped.valueX, "the message gives room to an action that left its line");
            compare(message.y, Theme.row.height + Theme.field.gap);
            compare(xIn(crampedUndo, cramped), cramped.valueX, "the action leaves the value column's start");
            compare(crampedUndo.mapToItem(cramped, 0, 0).y, message.y + message.height + Theme.field.gap, "the action is not the field gap under the message");
            compare(cramped.height, Theme.row.height + 2 * Theme.field.gap + message.height + crampedUndo.height + room());
            const beside = messageOf(roomy);
            compare(beside.width, Theme.field.labelWidth, "one more pixel keeps the action beside the message");
            compare(roomyUndo.mapToItem(roomy, 0, 0).x + roomyUndo.width, roomy.width);
            compare(roomy.height, Theme.row.height + Theme.field.gap + beside.height + room());
        }

        function test_a_hidden_action_takes_no_room() {
            const message = messageOf(acted);
            undo.visible = false;
            compare(message.width, acted.width - acted.valueX);
            compare(acted.height, Theme.row.height + Theme.field.gap + message.height + room());
            undo.visible = true;
            compare(message.width, acted.width - acted.valueX - undo.width - Theme.stack.inline);
        }

        // An action taller than the message, such as a RowAction in the
        // shell's font beside a hint, keeps the message's height, so
        // showing or hiding it moves no row below and no heading spaced
        // from the row's ink.
        function test_an_action_keeps_the_rows_height() {
            const message = messageOf(acted);
            verify(undo.visible && undo.height > message.height, "the action is no taller than the message");
            const shown = [acted.height, acted.inkBelow(), message.y];
            undo.visible = false;
            compare([acted.height, acted.inkBelow(), message.y], shown, "hiding the action moves the row's end, its ink or its message");
            undo.visible = true;
        }

        function test_a_row_without_a_message_draws_no_action() {
            verify(!quietUndo.visible, "an action draws with no message");
            compare(actedQuiet.height, Theme.row.height);
            actedQuiet.warning = "Set elsewhere";
            verify(quietUndo.visible, "the action stays hidden beside a message");
            actedQuiet.warning = "";
        }

        function test_a_long_message_wraps_in_the_value_column() {
            const message = messageOf(wrapped);
            verify(message.lineCount > 1, "the message stays on one line");
            compare(xIn(message, wrapped), wrapped.valueX);
            compare(message.width, wrapped.width - wrapped.valueX);
            verify(message.height > messageOf(warned).height);
            compare(wrapped.height, Theme.row.height + Theme.field.gap + message.height + room());
        }

        // expected-log: FormRow: no warningTone named "loud" -- the test names an unknown tone on purpose
        function test_a_message_draws_in_its_tone() {
            const message = messageOf(warned);
            const tones = [["warning", Theme.color.warning], ["danger", Theme.color.danger], ["muted", Theme.text.hint.color], ["loud", Theme.color.warning]];
            for (const [tone, colour] of tones) {
                warned.warningTone = tone;
                verify(Qt.colorEqual(message.color, colour), "tone " + tone + " draws " + message.color);
            }
            verify(!Qt.colorEqual(Theme.color.warning, Theme.color.danger) && !Qt.colorEqual(Theme.color.warning, Theme.text.hint.color), "the tones share a colour");
            warned.warningTone = "warning";
        }

        function test_without_a_label_column_the_control_takes_the_row() {
            verify(!labelOf(bare).visible, "the label draws without its column");
            compare(bare.valueX, 0);
            compare(xIn(thin, bare), 0);
            compare(thin.width, bare.width);
            compare(bare.height, thin.height);
            const message = messageOf(bareWarned);
            compare(thinWarned.mapToItem(bareWarned, 0, 0).y, 0);
            compare(xIn(message, bareWarned), 0);
            compare(message.y, thinWarned.height + Theme.field.gap);
            compare(bareWarned.height, thinWarned.height + Theme.field.gap + message.height + room());
        }

        function test_a_theme_moves_the_columns() {
            compare(UnitTheme.override({ field: { labelWidth: 80, labelGap: 5, gap: 9 }, row: { height: 44 } }), "ok");
            compare(xIn(choice, filled), 85);
            compare(choice.width, filled.width - 85);
            compare(plain.height, 44);
            compare(xIn(messageOf(warned), warned), 85);
            compare(messageOf(warned).y, 44 + 9);
        }

        // A message, a sub-text line, is followed by a group space; a row
        // without one keeps the column's spacing; the last row ends at its
        // message.
        function test_a_group_space_follows_a_message() {
            tryVerify(() => afterWarning.mapToItem(spaced, 0, 0).y - messageBottom(warnedFirst, spaced) === Theme.stack.group, 1000, "the row after a message");
            compare(plainNext.y - afterWarning.y, Theme.row.height + Theme.stack.row, "the row after a row without a message");
            compare(spaced.height, messageBottom(warnedLast, spaced), "the column's end after its last row");
        }

        function test_the_smoke_hook_names_the_row() {
            compare(plain.objectName, "fieldRow");
        }
    }
}
