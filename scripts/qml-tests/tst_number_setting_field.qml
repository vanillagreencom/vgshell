import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

Item {
    id: root
    width: 640
    height: 400
    property var written: []

    Component {
        id: numberField
        NumberSettingField {
            id: made
            onApply: next => {
                root.written = root.written.concat([next]);
                made.value = next;
            }
        }
    }

    UnitCase {
        name: "NumberSettingField"
        when: windowShown

        // The value column leaves exactly 80 pixels of handle travel with
        // a short readout, enough for 40 steps of two logical pixels.
        readonly property real boundaryWidth: 2 * Theme.field.paddingX + Theme.field.labelWidth +
            2 * Theme.field.labelGap + Theme.size.control.lg + Theme.slider.handle + 80

        function init() {
            UnitTheme.reset();
            root.written = [];
        }

        function findVisible(item, matches) {
            if (!item.visible) return undefined;
            if (matches(item)) return item;
            for (const child of item.children) {
                const found = findVisible(child, matches);
                if (found !== undefined) return found;
            }
            return undefined;
        }
        function sliderOf(item) { return findVisible(item, child => child instanceof Slider); }
        function inputOf(item) { return findVisible(item, child => child instanceof TextInput); }
        function hintOf(item) { return displayedTextItems(item).find(child => child instanceof LinkText && child.role === "hint" && child.plain !== ""); }
        function make(spec, value, width) {
            const made = createTemporaryObject(numberField, root, { spec: spec, value: value, width: width });
            verify(made !== null);
            verify(waitForPolish(made));
            return made;
        }
        function enter(input, value) {
            verify(input !== undefined);
            input.forceActiveFocus(Qt.TabFocusReason);
            input.text = value;
            keyClick(Qt.Key_Return);
        }

        function test_slider_requires_two_pixels_of_travel_per_step_data() {
            return [
                { tag: "exactly two pixels per step", max: 40, step: 1, widthDelta: 0, typed: false, travel: 80 },
                { tag: "one pixel narrower", max: 40, step: 1, widthDelta: -1, typed: true },
                { tag: "one more step", max: 41, step: 1, widthDelta: 0, typed: true },
                { tag: "continuous range", max: 10000, widthDelta: -1, typed: false }
            ];
        }
        function test_slider_requires_two_pixels_of_travel_per_step(data) {
            const spec = { type: "number", label: "Count", min: 0, max: data.max };
            if (data.step !== undefined) spec.step = data.step;
            const made = make(spec, 0, boundaryWidth + data.widthDelta);
            const slider = sliderOf(made);
            compare(slider === undefined, data.typed);
            compare(inputOf(made) !== undefined, data.typed);
            if (data.travel !== undefined) compare(slider.availableWidth - slider.handle.width, data.travel);
        }

        function test_the_spend_cap_states_its_range_and_accepts_an_exact_amount() {
            const made = make({ type: "number", label: "Weekly OpenAI spend cap", min: 0, max: 10000, step: 1 }, 80, 600);
            const input = inputOf(made);
            verify(input !== undefined);
            compare(hintOf(made).plain, "From 0 to 10,000");
            for (const text of ["10001", "-1", ""]) {
                enter(input, text);
                compare(root.written, []);
                compare(made.value, 80);
                compare(hintOf(made).plain, "Enter a number from 0 to 10,000.");
                compare(input.text, text);
                verify(made.edited);
                input.text = "25";
                compare(hintOf(made).plain, "From 0 to 10,000");
            }
            enter(input, "25");
            compare(root.written, [25]);
            compare(made.value, 25);
            verify(!made.edited);
        }

        function test_a_draft_survives_a_wider_allocation() {
            const made = make({ type: "number", label: "Count", min: 0, max: 40, step: 1 }, 0, boundaryWidth - 1);
            const input = inputOf(made);
            enter(input, "41");
            made.width = boundaryWidth;
            compare(inputOf(made), input);
            compare(input.text, "41");
            compare(root.written, []);
            enter(input, "40");
            compare(root.written, [40]);
            tryVerify(() => sliderOf(made) !== undefined);
        }

        function test_a_custom_row_can_enter_an_exact_time() {
            const made = make({ type: "number", label: "Lock after", min: 0, max: 86400, step: 30,
                unit: "seconds", allowCustom: true, presets: [{ value: 0, label: "Never" }, { value: 60 }] }, 450, 600);
            verify(made.customVisible);
            const input = inputOf(made);
            verify(input !== undefined);
            compare(input.text, "450");
            compare(hintOf(made).plain, "From 0 to 86,400 seconds");
            enter(input, "90000");
            compare(root.written, []);
            compare(hintOf(made).plain, "Enter a number from 0 to 86,400 seconds.");
            enter(input, "600");
            compare(root.written, [600]);
        }

        function test_range_help_keeps_bound_precision() {
            const made = make({ type: "number", label: "Level", min: 0.125, max: 1000.125, step: 1 }, 0.125, 600);
            verify(hintOf(made).plain.includes("0.125 to 1,000.125"));
        }
    }
}
