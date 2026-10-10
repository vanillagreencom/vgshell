import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// GroupList: the groups it holds sit `groupList.gap` apart with one
// hairline in `groupList.divider` centred in each gap, a hidden group takes
// neither, a group list inside another divides its own groups alike, and a
// theme moves both. The groups are the Settings page's own Status lines
// and Requirements rows, so the page's rhythm is read where it is drawn:
// a line's own lines, its value and its hint sit `field.gap` apart, less
// than the gap between groups. A state too long for the value column
// elides inside its chip, and its sentence wraps under it, both inside
// the line. A line that is a secret's presence draws Change key and
// Disconnect after its chip, or Add key on the value column while nothing
// is stored, and either opens the masked field, whose Save hands on what
// was typed.
Item {
    id: root
    width: 480
    height: 1560

    GroupList {
        id: list
        width: 400
        StatusLine { id: warden; width: list.width; label: "Warden"; tone: "success"; text: "Checking"; hint: "Keeps AI agents within their memory and task limits" }
        StatusLine { id: agents; width: list.width; label: "Agents running"; text: "3" }
        StatusLine { id: hidden; width: list.width; label: "Hidden"; text: "gone"; visible: false }
        RequirementRow { id: vsys; width: list.width; requirement: ({ name: "vsys", bus: null, state: "present", optional: false, purpose: "The agent dashboard that ships the warden" }) }
    }

    GroupList {
        id: outer
        y: 520
        width: 400
        StatusLine { id: single; width: outer.width; label: "Scheduler"; text: "systemd" }
        GroupList {
            id: inner
            width: outer.width
            StatusLine { id: tokens; width: inner.width; label: "Slack tokens"; hint: "One token per workspace" }
            StatusLine { id: acme; width: inner.width; label: "Acme"; tone: "success"; text: "Present" }
        }
    }

    // Status lines with a step: a short chip keeps the step beside it, a
    // chip too long for both puts the step under it.
    StatusLine { id: shortStep; x: 0; y: 760; width: 400; label: "Token"; tone: "warning"; text: "Absent"; actionLabel: "Set up token"; actionOffered: true }
    StatusLine { id: linedStep; x: 0; y: 880; width: 400; label: "Setup"; tone: "warning"; text: "Set up needed"; lines: ["The model is missing.", "The service is off."]; actionLabel: "Set up"; actionOffered: true }
    StatusLine { id: shortText; x: 0; y: 1080; width: 400; label: "Mode"; text: "Local"; actionLabel: "Change"; actionOffered: true }
    StatusLine { id: longText; x: 0; y: 1140; width: 400; label: "Model"; text: "A model name far too long to share its line with the step beside it"; actionLabel: "Choose a model"; actionOffered: true }
    StatusLine { id: longHint; x: 0; y: 1000; width: 400; label: "Accounts"; hint: "Signed in does not prove that the AI answers. A test request may cost money, so check it yourself." }
    StatusLine { id: longStep; x: 0; y: 820; width: 400; label: "While logged out"; tone: "warning"; text: "Automations run only while you are logged in"; actionLabel: "Enable while logged out"; actionOffered: true }
    StatusLine { id: longState; x: 0; y: 1220; width: 260; label: "Check"; tone: "danger"; text: "The update check failed. Select Refresh to try again."; hint: "The update source could not be reached. Check your connection and select Refresh." }

    StatusLine { id: storedKey; x: 0; y: 1420; width: 400; label: "Acme"; tone: "success"; text: "Present"; access: "disconnect"; secretLabel: "Acme key" }
    StatusLine { id: absentKey; x: 0; y: 1480; width: 400; label: "Globex"; access: "connect"; secretLabel: "Acme key" }
    SignalSpy { id: stores; target: storedKey; signalName: "storeSecret" }

    TestCase {
        name: "grouplist"
        when: windowShown

        function init() { UnitTheme.reset(); hidden.visible = false; }

        function hairlinesOf(owner) {
            return owner.children.filter(child => child.vertical !== undefined && child.visible);
        }

        function shownGroups(owner) {
            const column = owner.children.find(child => child.spacing !== undefined);
            return column.children.filter(child => child.visible && child.width > 0 && child.height > 0);
        }

        // What breaks the rule that each gap between two shown groups is
        // `groupList.gap`, with one hairline centred in it, in its own
        // colour, across the list; [] when it holds. A positioner lays out
        // a turn after a change, so a check waits for it.
        function dividedProblems(owner) {
            const groups = shownGroups(owner);
            const lines = hairlinesOf(owner);
            const out = [];
            if (lines.length !== groups.length - 1) return ["hairlines=" + lines.length + " groups=" + groups.length];
            for (let i = 1; i < groups.length; i++) {
                const top = groups[i - 1].y + groups[i - 1].height;
                const line = lines[i - 1];
                if (groups[i].y - top !== Theme.groupList.gap) out.push("gap" + i + "=" + (groups[i].y - top));
                if (line.height !== Theme.divider.thickness || line.width !== owner.width) out.push("hairline" + i + ".size=" + line.width + "x" + line.height);
                if (Math.abs(line.y + line.height / 2 - (top + groups[i].y) / 2) > 0.5) out.push("hairline" + i + ".y=" + line.y + " between " + top + " and " + groups[i].y);
                if (String(line.color) !== String(Qt.color(Theme.groupList.divider))) out.push("hairline" + i + ".color=" + line.color);
            }
            return out;
        }
        function checkDivided(owner) {
            tryVerify(() => dividedProblems(owner).length === 0, 1000, "the groups are divided: " + JSON.stringify(dividedProblems(owner)));
        }

        function test_groups_are_divided() {
            compare(shownGroups(list).length, 3);
            checkDivided(list);
            verify(Theme.groupList.gap > Theme.field.gap, "groups sit farther apart than the lines of one");
        }

        // A hidden group takes no gap and no hairline, and one shown again
        // takes both.
        function test_a_hidden_group_takes_no_hairline() {
            checkDivided(list);
            compare(hairlinesOf(list).length, 2);
            hidden.visible = true;
            checkDivided(list);
            compare(hairlinesOf(list).length, 3);
        }

        function test_a_nested_list_divides_its_own_groups() {
            checkDivided(outer);
            checkDivided(inner);
            compare(hairlinesOf(outer).length, 1);
            compare(hairlinesOf(inner).length, 1);
        }

        function test_a_theme_moves_the_gap_and_the_hairline() {
            compare(UnitTheme.override({ groupList: { gap: 20, divider: "#ff000080" } }), "ok");
            compare(Theme.groupList.gap, 20);
            checkDivided(list);
            compare(String(hairlinesOf(list)[0].color), String(Qt.color("#80ff0000")));
        }

        // The lines of one group sit `field.gap` apart: the key/value row
        // and its hint.
        // The step's RowAction and the value's chip of a status line, in
        // the line's frame.
        function stepOf(line) { return findChild(line, RowAction); }
        function chipOf(line) { return findChild(line, Badge); }
        function findChild(item, type) {
            for (const child of item.children) {
                if (child instanceof type && child.visible) return child;
                const found = findChild(child, type);
                if (found !== null) return found;
            }
            return null;
        }
        function box(item, line) { const at = item.mapToItem(line, 0, 0); return { x: at.x, y: at.y, right: at.x + item.width, bottom: at.y + item.height }; }

        function test_a_step_stands_beside_a_short_value_and_under_a_long_one() {
            const chip = box(chipOf(shortStep), shortStep), step = box(stepOf(shortStep), shortStep);
            compare(step.x, chip.right + Theme.stack.inline, "the step stands right after the chip");
            fuzzyCompare(step.y + (step.bottom - step.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            const longChip = box(chipOf(longStep), longStep), longAction = box(stepOf(longStep), longStep);
            verify(longAction.y >= longChip.bottom, "the step sits under a chip too long for both");
            compare(longAction.x, longChip.x, "the step starts on the value column");
        }

        // A step beside a chip with further lines centres on the first
        // chip, and a hint that stands as the value grows the row with
        // its wrapped lines.
        function test_a_step_centres_on_the_first_chip_and_a_wrapped_value_fits() {
            const chip = box(chipOf(linedStep), linedStep), step = box(stepOf(linedStep), linedStep);
            fuzzyCompare(step.y + (step.bottom - step.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            const hint = findChild(longHint, Label);
            let wrapped = null;
            for (const item of [longHint]) {
                const stack = [item];
                while (stack.length > 0) {
                    const at = stack.pop();
                    if (at.role === "hint" && at.text !== "" && at.visible) wrapped = at;
                    for (const child of at.children) stack.push(child);
                }
            }
            verify(wrapped !== null && wrapped.lineCount > 1, "the hint wraps");
            verify(box(wrapped, longHint).bottom <= longHint.height + 0.5, "the row holds every wrapped line");
        }

        // A text value with a step: the step stands beside a short text,
        // and under a text too long for both, which then takes the whole
        // value column; the choice is the same however the line is built.
        function test_a_text_value_keeps_its_step_beside_or_under() {
            // The line's shown text in the value role.
            const value = line => {
                const stack = [line];
                while (stack.length > 0) {
                    const at = stack.shift();
                    if (at !== line && at.role === "value" && at.visible) return at;
                    for (const child of at.children) stack.push(child);
                }
                return null;
            };
            const shortValue = box(value(shortText), shortText), shortAction = box(stepOf(shortText), shortText);
            compare(shortAction.x, shortValue.right + Theme.stack.inline, "the step stands right after a short text");
            const longValue = box(value(longText), longText), longAction = box(stepOf(longText), longText);
            verify(longAction.y >= longValue.bottom, "the step sits under a text too long for both");
            compare(longAction.x, longValue.x, "the step starts on the value column");
            longText.width = 0;
            longText.width = 400;
            tryVerify(() => box(stepOf(longText), longText).y >= box(value(longText), longText).bottom, 1000, "the step stays under the text after a relayout");
        }

        // A state too long for the value column keeps its chip, and the
        // chip's label, inside the line; its sentence wraps under it,
        // inside the line too.
        function test_a_long_state_and_its_sentence_stay_inside_the_line() {
            const chip = chipOf(longState);
            const chipBox = box(chip, longState);
            verify(chipBox.right <= longState.width + 0.5, "the chip ends inside the line: " + chipBox.right + " > " + longState.width);
            verify(chip.width < chip.implicitWidth, "the fixture's state is too long for the value column");
            const label = chip.children.find(child => child.role === "label");
            verify(label !== undefined, "the chip holds its label");
            verify(label.truncated, "the label elides");
            verify(box(label, longState).x + label.contentWidth <= chipBox.right + 0.5, "the label's text ends inside the chip");
            let sentence = null;
            const stack = [longState];
            while (stack.length > 0) {
                const at = stack.pop();
                if (at.role === "hint" && at.text === longState.hint && at.visible) sentence = at;
                for (const child of at.children) stack.push(child);
            }
            verify(sentence !== null, "the line draws its sentence");
            verify(sentence.lineCount > 1, "the sentence wraps");
            const sentenceBox = box(sentence, longState);
            verify(sentenceBox.y >= chipBox.bottom, "the sentence sits under the chip");
            verify(sentenceBox.x + sentence.contentWidth <= longState.width + 0.5, "the sentence ends inside the line");
            verify(sentenceBox.bottom <= longState.height + 0.5, "the line holds every wrapped line of the sentence");
        }

        // A stored secret's line: its chip, Change key and Disconnect on
        // one centre, `stack.inline` apart. A secret nothing is stored for
        // draws no chip, and Add key starts on the value column.
        function test_a_secret_line_draws_its_steps() {
            const chip = box(chipOf(storedKey), storedKey);
            const change = findChild(storedKey, IconButton), disconnect = stepOf(storedKey);
            verify(change !== null, "a stored secret's line draws Change key");
            verify(disconnect !== null && disconnect.text === "Disconnect", "a stored secret's line draws Disconnect");
            const changeBox = box(change, storedKey), actionBox = box(disconnect, storedKey);
            compare(changeBox.x, chip.right + Theme.stack.inline, "Change key stands right after the chip");
            compare(actionBox.x, changeBox.right + Theme.stack.inline, "Disconnect stands right after Change key");
            fuzzyCompare(changeBox.y + (changeBox.bottom - changeBox.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            fuzzyCompare(actionBox.y + (actionBox.bottom - actionBox.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            compare(chipOf(absentKey), null, "a secret nothing is stored for draws no chip");
            compare(findChild(absentKey, IconButton), null, "it draws no Change key");
            const add = stepOf(absentKey);
            verify(add !== null && add.text === "Add key", "it draws Add key");
            const field = absentKey.children.find(child => child.valueX !== undefined);
            compare(box(add, absentKey).x, field.valueX, "Add key starts on the value column");
        }

        // Change key and Add key open the masked field in the steps'
        // place; Enter hands on what was typed and closes it, and Escape
        // closes it with nothing handed on.
        function test_a_secret_step_opens_the_masked_field() {
            stores.clear();
            compare(findChild(storedKey, TextField), null, "a closed line holds no field");
            findChild(storedKey, IconButton).clicked();
            tryVerify(() => findChild(storedKey, TextField) !== null, 1000, "Change key opens the field");
            const field = findChild(storedKey, TextField);
            verify(field.password, "the field masks what is typed");
            compare(field.text, "", "the field opens empty");
            compare(findChild(storedKey, IconButton), null, "the steps hide while the field is open");
            field.text = "typed-key";
            field.accepted();
            compare(stores.count, 1);
            compare(stores.signalArguments[0][0], "typed-key");
            tryVerify(() => findChild(storedKey, TextField) === null, 1000, "Save closes the field");
            stepOf(absentKey).clicked();
            tryVerify(() => findChild(absentKey, TextField) !== null, 1000, "Add key opens the field");
            keyClick(Qt.Key_Escape);
            tryVerify(() => findChild(absentKey, TextField) === null, 1000, "Escape closes the field");
            compare(stores.count, 1, "a closed field hands on nothing");
        }

        function test_a_groups_own_lines_sit_close() {
            const field = warden.children.find(child => child.valueX !== undefined);
            verify(field !== undefined, "the line holds its field");
            compare(warden.spacing, Theme.field.gap);
            const row = field.children.find(child => child.objectName === "fieldRow");
            const hint = field.children.find(child => child.height > 0 && child.children.length > 0 && child.children[0].role === "hint");
            verify(row !== undefined && hint !== undefined, "the field holds its row and its hint");
            compare(hint.y - (row.y + row.height), Theme.field.gap);
        }
    }
}
