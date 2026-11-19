import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit

// FormRow: the label column is `field.labelWidth` wide and the control
// starts `field.labelGap` after it and ends at the bounded allocation; the row
// box is `row.height` tall unless its control is taller; the label sits by
// capital height and the control by its box; beside a control that wraps
// into lines, a RowActions, a one-line label and its info button sit on
// the first line, where they sit in a one-line row, and that line's
// actions sit where a one-line row's do, while beside a control that is
// one taller box they centre on the box; a message draws as hint text
// under the value column, `field.gap` below its control's drawn ink, the
// same blank rows under a switch, a slider and a segmented control, and
// wrapped to the column, in its tone's colour, or in the role `warningRole`
// names, ends the row with the lower of the row box and itself, and moves
// neither the label nor the control; an action draws on
// the message's line, on the row's end edge, the message wrapping before
// it, only while the row has a message and the action shows, at the
// message's height so it moves no row below it, and goes on a
// line of its own under the message where it would leave the message less
// than the label column's width, and its focus ring crosses no drawn row
// of the control above; without a label
// column the control takes the full width at its own height; the smoke's
// `fieldRow` hook names the row. A row with a message is followed by a group
// space, `stack.group`, before the next item of its column that is no
// key/value row, unless it is the last; the rows of the first column sit
// 0 apart, so each with a message there grows by
// the group space under its message. A page reference in the message or in
// the info dialog's text asks for its page and tab through
// `warningPageActivated` or `infoPageActivated`. Help belongs to the
// dotted label, with an independent focus target and no hover tooltip.

Item {
    id: root
    width: 480
    height: 1300

    // A Flow, which no key/value row stands in by ink, so each row's box
    // starts at the row's top: rows of a Column stand `stack.page` apart
    // by ink (FormRow `inkTop`), which tst_settingfield.qml reads.
    Flow {
        width: 420
        FormRow { id: plain; width: parent.width; label: "Clock"; Switch { id: toggle; size: "sm" } }
        FormRow { id: filled; width: parent.width; label: "Format"; Select { id: choice; width: parent.width; model: ["HH:mm", "hh:mm ap"] } }
        FormRow { id: tall; width: parent.width; label: "Preview"; Rectangle { id: block; width: 40; height: Theme.row.height + 24; color: "transparent" } }
        FormRow { id: warned; width: parent.width; label: "Speed"; warning: "Overridden"; Slider { id: speed; width: parent.width; from: 0; to: 1; value: 0.5 } }
        FormRow { id: wrapped; width: parent.width; label: "Scroll"; warning: "A message too long for one line of the value column wraps inside it and never runs under the label column"; Switch { id: wrappedToggle; size: "sm" } }
        FormRow { id: bare; width: parent.width; label: "Hidden"; labelColumn: false; Rectangle { id: thin; width: parent.width; height: 8; color: "transparent" } }
        FormRow { id: bareWarned; width: parent.width; labelColumn: false; warning: "Refused"; Rectangle { id: thinWarned; width: parent.width; height: 8; color: "transparent" } }
        FormRow { id: acted; width: parent.width; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: undo; width: 90; height: 30; color: "transparent" } Switch { id: actedToggle; size: "sm" } }
        FormRow { id: actedQuiet; width: parent.width; label: "Speed"; action: Rectangle { id: quietUndo; width: 90; height: 30; color: "transparent" } Switch { size: "sm" } }
        FormRow { id: cramped; width: 2 * Theme.field.labelWidth + Theme.field.labelGap + Theme.stack.inline + crampedUndo.width - 1; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: crampedUndo; width: 90; height: 30; color: "transparent" } Switch { id: crampedToggle; size: "sm" } }
        FormRow { id: roomy; width: cramped.width + 1; label: "Speed"; warning: "Set elsewhere"; action: Rectangle { id: roomyUndo; width: 90; height: 30; color: "transparent" } Switch { id: roomyToggle; size: "sm" } }
        Badge { id: chip; text: "Chip" }
    }

    Column {
        id: spaced
        y: 640
        width: 420
        spacing: Theme.stack.row
        // Rows with no label column are no key/value rows, so they keep the
        // column's spacing and a message's group space.
        FormRow { id: warnedFirst; width: parent.width; labelColumn: false; warning: "Overridden"; Rectangle { width: 40; height: Theme.row.height; color: "transparent" } }
        FormRow { id: afterWarning; width: parent.width; labelColumn: false; Rectangle { width: 40; height: Theme.row.height; color: "transparent" } }
        FormRow { id: plainNext; width: parent.width; labelColumn: false; Rectangle { width: 40; height: Theme.row.height; color: "transparent" } }
        FormRow { id: warnedLast; width: parent.width; labelColumn: false; warning: "Overridden"; Rectangle { width: 40; height: Theme.row.height; color: "transparent" } }
    }

    FormRow { id: roled; y: 840; width: 420; label: "Speed"; warning: "Overridden"; warningRole: "tooltip"; Switch { size: "sm" } }
    FormRow {
        id: explainedLabel
        y: 860
        width: 420
        label: "Shortcut"
        labelTooltip: "Change its keyboard shortcut."
        info: "See [its settings](page:acme.keys/Settings)."
        Label { role: "value"; text: "Available" }
    }

    // Room for two of the three actions.
    FormRow {
        id: lined
        y: 900
        width: 420
        label: "Actions"
        info: "Each opens a screen."
        RowActions {
            id: steps
            width: stepOne.width + Theme.rowAction.gap + stepTwo.width
            RowAction { id: stepOne; text: "Install" }
            RowAction { id: stepTwo; text: "Update" }
            RowAction { id: stepThree; text: "Remove" }
        }
    }
    FormRow {
        id: single
        y: 1000
        width: 420
        label: "Manage"
        info: "Each opens a screen."
        RowActions {
            RowAction { id: lone; text: "Install" }
            RowAction { text: "Update" }
        }
    }

    FormRow {
        id: paged
        y: 1540
        width: 420
        label: "Voice"
        warning: "Set it up on the [Voice page](page:acme.voice/Setup)."
        info: "Keys are on the [Models page](page:acme.models/Keys)."
        Switch { size: "sm" }
    }
    SignalSpy { id: warningPages; target: paged; signalName: "warningPageActivated" }
    SignalSpy { id: infoPages; target: paged; signalName: "infoPageActivated" }

    // Rows with the message a value's source draws in Settings, under a
    // switch, a slider and a segmented control, over the rest of the
    // window, so the image holds only their ink on the surface colour.
    Component {
        id: coveredMessages
        Rectangle {
            property alias rows: messageRows
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: messageRows
                width: 420
                spacing: Theme.stack.group
                FormRow { label: "Animations"; width: parent.width; warning: "Set by theme"; warningRole: "tooltip"; warningTone: "muted"; Switch { size: "sm"; checked: true } }
                FormRow { label: "Speed"; width: parent.width; warning: "Set by theme"; warningRole: "tooltip"; warningTone: "muted"; Slider { width: parent.width; from: 0; to: 1; value: 0.5 } }
                FormRow { label: "Curve"; width: parent.width; warning: "Set by theme"; warningRole: "tooltip"; warningTone: "muted"; SegmentedControl { model: ["Linear", "Smooth", "Snappy"] } }
            }
        }
    }

    // Rows whose message carries a RowAction, as a value's source draws
    // them in Settings, under a slider with a reading and a switch, over the
    // rest of the window, so the image holds only their ink.
    Component {
        id: actedMessages
        Rectangle {
            property alias rows: actedRows
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: actedRows
                width: 420
                spacing: Theme.stack.group
                FormRow {
                    label: "Gaps"; width: parent.width; warning: "Set by you"; warningRole: "tooltip"; warningTone: "muted"
                    action: RowActions { RowAction { text: "Use theme value" } }
                    SavedSlider { width: parent.width; from: 0; to: 32; shown: 20; formatValue: value => Math.round(value) + " px" }
                }
                FormRow {
                    label: "Animations"; width: parent.width; warning: "Set by you"; warningRole: "tooltip"; warningTone: "muted"
                    action: RowActions { RowAction { text: "Use theme value" } }
                    Switch { size: "sm"; checked: true }
                }
            }
        }
    }

    UnitCase {
        name: "formrow"
        when: windowShown

        function labelOf(row) { return semanticLabelItems(row, true)[0]; }
        function messageOf(row) { return displayedTextItems(row, true).find(child => child.role === "hint"); }
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
        // Where CONTROL's drawn ink ends in ROW, on a whole pixel row, and
        // where the row's message starts: `field.gap` under it.
        function inkEnd(control, row) { return Math.ceil(control.mapToItem(row, 0, control.height).y - Theme.inkBelow(control)); }
        function messageTop(control, row) { return inkEnd(control, row) + Theme.field.gap; }
        function messageBottom(row, item) {
            const message = messageOf(row);
            return message.mapToItem(item, 0, message.height).y;
        }

        function test_label_help_is_one_independent_target() {
            const help = labelOf(explainedLabel);
            verify(help instanceof InfoButton);
            compare(help.info, explainedLabel.labelTooltip + "\n" + explainedLabel.info);
            compare(help.activeFocusOnTab, true);
            help.forceActiveFocus(Qt.TabFocusReason);
            compare(help.visualFocus, true);
            compare(help.width, Theme.field.labelWidth);
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
            const message = displayedTextItems(roled).find(child => child.role === "tooltip");
            verify(message !== undefined && message.visible, "the row draws no message in the role it names");
            verify(messageOf(roled) === undefined, "the row draws a hint message too");
        }

        function test_a_taller_control_grows_the_row() {
            compare(tall.height, block.height);
            compare(block.mapToItem(tall, 0, 0).y, 0);
        }

        // A one-box control keeps the label and the info button on the
        // centre of its box.
        function test_a_taller_box_keeps_the_label_on_its_centre() {
            verify(tall.height > Theme.row.height, "the control is no taller than a row");
            compare(labelOf(tall).y, labelOf(tall).topForCapCenter(tall.height));
        }

        function test_a_wrapped_control_keeps_the_row_pitch_and_the_label_on_its_first_line() {
            verify(steps.width <= lined.width - lined.valueX, "the actions' two lines pass the value column");
            verify(Theme.stack.row > 0, "the rows of a page stand no gap apart, so a dropped line gap reads alike");
            compare(lined.height, 2 * Theme.row.height + Theme.stack.row);
            compare(single.height, Theme.row.height);
            const firstLine = stepOne.mapToItem(lined, 0, stepOne.height / 2).y;
            fuzzyCompare(firstLine, Theme.row.height / 2, 0.5, "the first line leaves a row's centre");
            compare(stepOne.mapToItem(lined, 0, 0).y, lone.mapToItem(single, 0, 0).y, "the first line leaves a one-line row's place");
            compare(stepThree.mapToItem(lined, 0, 0).y - stepOne.mapToItem(lined, 0, 0).y, Theme.row.height + Theme.stack.row, "the lines leave the pitch of a page's rows");
            // A RowAction's box centres on its text's capital centre.
            fuzzyCompare(labelOf(lined).y + labelOf(lined).capCentre, firstLine, 1, "the label's capitals leave the first line's");
            compare(labelOf(lined).y, labelOf(single).y, "the label leaves a one-line row's place");
            verify(labelOf(lined).height > 0, "the row draws no help label");
            compare(labelOf(lined).y, labelOf(single).y, "the help label leaves a one-line row's place");
            compare(lined.inkBelow, lined.height - stepThree.mapToItem(lined, 0, stepThree.height).y + stepThree.inkBelow);
            compare(lined.inkAbove, Math.min(labelOf(lined).y + labelOf(lined).inkAbove, stepOne.mapToItem(lined, 0, 0).y + stepOne.inkAbove));
        }

        function test_a_message_sits_under_the_value_column() {
            const message = messageOf(warned);
            verify(message.visible, "the row draws no message");
            compare(message.role, "hint");
            compare(xIn(message, warned), warned.valueX);
            compare(xIn(message, warned) + message.width, warned.width);
            compare(message.y, messageTop(speed, warned), "the message starts the field gap below the slider's ink");
            verify(message.y < Theme.row.height, "the message waits for the row box's end under a slider that draws less than its box");
            verify(message.height > 0);
            compare(warned.implicitHeight, message.y + message.height + room(), "the row ends with its message");
            compare(warned.height, warned.implicitHeight);
            compare(typesUnder(chip)[0], "Badge", "the reader names no chip");
            verify(typesUnder(warned).indexOf("Badge") === -1, "the row draws a chip");
        }

        function inked(img, x, y) {
            const bg = Qt.color(Theme.color.surface);
            return Math.abs(img.red(x, y) - Math.round(bg.r * 255)) > 8 || Math.abs(img.green(x, y) - Math.round(bg.g * 255)) > 8
                || Math.abs(img.blue(x, y) - Math.round(bg.b * 255)) > 8;
        }
        function rowInked(img, y, from, to) {
            for (let x = from; x < to; x++) if (inked(img, x, y)) return true;
            return false;
        }

        // A message stands `field.gap` under its control's drawn ink, so
        // the blank pixel rows between a control's lowest inked row and its
        // message's highest, read across the value column, are the same
        // under a switch, a slider and a segmented control: the gap plus
        // the message's own blank rows above its glyphs, 7 in this run. Placed
        // `field.gap` under the row box, the messages read 17, 18 and 9.
        function test_a_message_stands_the_field_gap_under_every_controls_ink() {
            const cover = createTemporaryObject(coveredMessages, root);
            verify(cover !== null);
            verify(renderedFrame(cover));
            const img = grabImage(root);
            const read = cover.rows.children.filter(item => item.objectName === "fieldRow").map(row => {
                const message = displayedTextItems(row).find(child => child instanceof LinkText && !(child instanceof InfoButton));
                verify(message.visible, "the row draws no message");
                const from = Math.round(row.mapToItem(root, row.valueX, 0).x);
                const to = Math.round(row.mapToItem(root, row.width, 0).x);
                const box = Math.round(message.mapToItem(root, 0, 0).y);
                let glyphs = box;
                while (glyphs < box + message.height && !rowInked(img, glyphs, from, to)) glyphs++;
                verify(glyphs < box + message.height, "the message draws no ink: " + row.label);
                let blank = glyphs;
                while (blank > 0 && !rowInked(img, blank - 1, from, to)) blank--;
                return { label: row.label, gap: glyphs - blank, above: glyphs - box };
            });
            compare(read.length, 3);
            const text = read.map(entry => entry.label + " " + entry.gap).join(", ");
            for (const entry of read)
                compare(entry.gap, Theme.field.gap + entry.above, "every message stands the field gap under its control's ink: " + text);
        }

        function changed(a, b, x, y) {
            return Math.abs(a.red(x, y) - b.red(x, y)) > 8 || Math.abs(a.green(x, y) - b.green(x, y)) > 8 || Math.abs(a.blue(x, y) - b.blue(x, y)) > 8;
        }

        // A message's action centres on the message's line and is taller
        // than it, so its box rises toward the control; its focus ring
        // stands clear of what the action draws and crosses no drawn row of
        // the control. Read from the image: the control's lowest inked row
        // with the action hidden, and the ring's highest, the first row the
        // ring changes, beside a slider with its reading and a switch.
        function test_a_message_actions_ring_crosses_no_part_of_its_control() {
            const cover = createTemporaryObject(actedMessages, root);
            verify(cover !== null);
            const rows = cover.rows.children.filter(item => item.objectName === "fieldRow");
            compare(rows.length, 2);
            const read = rows.map(row => {
                const actions = row.actionItem;
                verify(actions !== null, "the row draws no action: " + row.label);
                const action = actions.shown[0];
                const message = displayedTextItems(row).find(child => child instanceof LinkText && !(child instanceof InfoButton));
                const from = Math.round(row.mapToItem(root, row.valueX, 0).x);
                const to = Math.round(row.mapToItem(root, row.width, 0).x);

                actions.visible = false;
                verify(renderedFrame(cover));
                const bare = grabImage(root);
                const box = Math.round(message.mapToItem(root, 0, 0).y);
                let glyphs = box;
                while (glyphs < box + message.height && !rowInked(bare, glyphs, from, to)) glyphs++;
                verify(glyphs < box + message.height, "the message draws no ink: " + row.label);
                let control = glyphs;
                while (control > 0 && !rowInked(bare, control - 1, from, to)) control--;
                control--;

                actions.visible = true;
                verify(renderedFrame(cover));
                const resting = grabImage(root);
                action.focusPreview = true;
                verify(renderedFrame(cover));
                const ringed = grabImage(root);
                const ring = action.background.children[0].children[0];
                verify(ring.visible, "the action draws no ring: " + row.label);
                action.focusPreview = false;
                const left = Math.max(0, Math.floor(ring.mapToItem(root, 0, 0).x));
                const right = Math.min(root.width, Math.ceil(ring.mapToItem(root, ring.width, 0).x));
                let top = -1;
                for (let y = 0; y < root.height && top < 0; y++)
                    for (let x = left; x < right && top < 0; x++)
                        if (changed(resting, ringed, x, y)) top = y;
                verify(top >= 0, "the ring changes no pixel: " + row.label);
                return { label: row.label, ring: top, control: control };
            });
            const text = read.map(entry => entry.label + ": ring top " + entry.ring + ", control's lowest ink " + entry.control).join("; ");
            for (const entry of read)
                verify(entry.ring > entry.control, "the action's ring crosses its control's ink: " + text);
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
            compare(message.y, messageTop(actedToggle, acted));
            compare(acted.height, message.y + message.height + room(), "the row grows for a taller action");
            fuzzyCompare(centreIn(message, acted), centreIn(undo, acted), 1, "the message leaves the action's line");
            fuzzyCompare(centreIn(actedToggle, acted), Theme.row.height / 2, 1, "the control leaves the row box's centre");
        }

        // The value column of `cramped` is one pixel short of the label
        // column's width beside the action; `roomy` has that pixel.
        function test_an_action_with_no_room_beside_the_message_goes_under_it() {
            const message = messageOf(cramped);
            compare(message.width, cramped.width - cramped.valueX, "the message gives room to an action that left its line");
            compare(message.y, messageTop(crampedToggle, cramped));
            compare(xIn(crampedUndo, cramped), cramped.valueX, "the action leaves the value column's start");
            compare(crampedUndo.mapToItem(cramped, 0, 0).y, message.y + message.height + Theme.field.gap, "the action is not the field gap under the message");
            compare(cramped.height, message.y + message.height + Theme.field.gap + crampedUndo.height + room());
            const beside = messageOf(roomy);
            compare(beside.width, Theme.field.labelWidth, "one more pixel keeps the action beside the message");
            compare(roomyUndo.mapToItem(roomy, 0, 0).x + roomyUndo.width, roomy.width);
            compare(beside.y, messageTop(roomyToggle, roomy));
            compare(roomy.height, beside.y + beside.height + room());
        }

        function test_a_hidden_action_takes_no_room() {
            const message = messageOf(acted);
            undo.visible = false;
            compare(message.width, acted.width - acted.valueX);
            compare(acted.height, messageTop(actedToggle, acted) + message.height + room());
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
            const shown = [acted.height, acted.inkBelow, message.y];
            undo.visible = false;
            compare([acted.height, acted.inkBelow, message.y], shown, "hiding the action moves the row's end, its ink or its message");
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
            compare(message.y, messageTop(wrappedToggle, wrapped));
            compare(wrapped.height, message.y + message.height + room());
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
            compare(thin.width, Math.min(bare.width, Theme.control.maxWidth));
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
            compare(choice.width, Math.min(filled.width - 85, Theme.control.maxWidth));
            compare(plain.height, 44);
            compare(xIn(messageOf(warned), warned), 85);
            compare(messageOf(warned).y, inkEnd(speed, warned) + 9);
        }

        // A message, a sub-text line, is followed by a group space; a row
        // without one keeps the column's spacing; the last row ends at its
        // message.
        function test_a_group_space_follows_a_message() {
            tryVerify(() => afterWarning.mapToItem(spaced, 0, 0).y - messageBottom(warnedFirst, spaced) === Theme.stack.group, 1000, "the row after a message");
            compare(plainNext.y - afterWarning.y, Theme.row.height + Theme.stack.row, "the row after a row without a message");
            compare(spaced.height, messageBottom(warnedLast, spaced), "the column's end after its last row");
        }

        function test_a_message_page_reference_asks_for_its_page() {
            warningPages.clear();
            const message = messageOf(paged);
            compare(message.linked, true, "the reference's words are a link");
            message.clicked();
            compare(warningPages.count, 1);
            compare(warningPages.signalArguments[0][0], "acme.voice");
            compare(warningPages.signalArguments[0][1], "Setup");
        }

        function test_an_info_page_reference_asks_for_its_page() {
            infoPages.clear();
            const label = labelOf(paged);
            const link = helpParagraphs(label, root).find(child => child.linked);
            verify(link !== undefined);
            label.openInfo();
            link.clicked();
            compare(label.infoOpen, false);
            compare(infoPages.count, 1);
            compare(Array.from(infoPages.signalArguments[0]), ["acme.models", "Keys"]);
        }

        function test_the_smoke_hook_names_the_row() {
            compare(plain.objectName, "fieldRow");
        }
    }
}
