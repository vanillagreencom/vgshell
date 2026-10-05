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
// column, in its tone's colour, grows the row by the gap and its own
// height, and moves neither the label nor the control; without a label
// column the control takes the full width at its own height; the smoke's
// `fieldRow` hook names the row.
Item {
    id: root
    width: 480
    height: 600

    Column {
        width: 420
        FormRow { id: plain; width: parent.width; label: "Clock"; Switch { id: toggle; size: "sm" } }
        FormRow { id: filled; width: parent.width; label: "Format"; Select { id: choice; width: parent.width; model: ["HH:mm", "hh:mm ap"] } }
        FormRow { id: tall; width: parent.width; label: "Preview"; Rectangle { id: block; width: 40; height: Theme.row.height + 24; color: "transparent" } }
        FormRow { id: warned; width: parent.width; label: "Speed"; warning: "Overridden"; Slider { id: speed; width: parent.width; from: 0; to: 1; value: 0.5 } }
        FormRow { id: wrapped; width: parent.width; label: "Scroll"; warning: "A message too long for one line of the value column wraps inside it and never runs under the label column"; Switch { size: "sm" } }
        FormRow { id: bare; width: parent.width; label: "Hidden"; labelColumn: false; Rectangle { id: thin; width: parent.width; height: 8; color: "transparent" } }
        FormRow { id: bareWarned; width: parent.width; labelColumn: false; warning: "Refused"; Rectangle { id: thinWarned; width: parent.width; height: 8; color: "transparent" } }
        Badge { id: chip; text: "Chip" }
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
            compare(warned.implicitHeight, Theme.row.height + Theme.field.gap + message.height);
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

        function test_a_long_message_wraps_in_the_value_column() {
            const message = messageOf(wrapped);
            verify(message.lineCount > 1, "the message stays on one line");
            compare(xIn(message, wrapped), wrapped.valueX);
            compare(message.width, wrapped.width - wrapped.valueX);
            verify(message.height > messageOf(warned).height);
            compare(wrapped.height, Theme.row.height + Theme.field.gap + message.height);
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
            compare(bareWarned.height, thinWarned.height + Theme.field.gap + message.height);
        }

        function test_a_theme_moves_the_columns() {
            compare(UnitTheme.override({ field: { labelWidth: 80, labelGap: 5, gap: 9 }, row: { height: 44 } }), "ok");
            compare(xIn(choice, filled), 85);
            compare(choice.width, filled.width - 85);
            compare(plain.height, 44);
            compare(xIn(messageOf(warned), warned), 85);
            compare(messageOf(warned).y, 44 + 9);
        }

        function test_the_smoke_hook_names_the_row() {
            compare(plain.objectName, "fieldRow");
        }
    }
}
