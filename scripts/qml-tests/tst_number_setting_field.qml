import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// NumberSettingField's editor for a bounded number with no presets, and the
// custom row under presets: a slider while its widest rail gives each step
// two pixels or more, else a text field whose hint states the range and
// which refuses a typed value outside it with an error line and writes
// nothing (docs/architecture/design-system.md § Settings pages). The widest
// rail is the documented one: `control.maxWidth` less the reading's least
// room, `size.control.lg`, and its gap, `field.labelGap`.
Item {
    id: root
    width: 640
    height: 400

    property var written: []

    Component {
        id: numberField
        NumberSettingField {
            id: made
            width: 600
            // The owner accepts every write, as the core does a number.
            onApply: next => { root.written = root.written.concat([next]); made.value = next; }
        }
    }

    UnitCase {
        name: "numbersettingfield"
        when: windowShown

        // The most steps a slider takes: two pixels of its widest rail each.
        readonly property int limit: Math.floor((Theme.control.maxWidth - Theme.size.control.lg - Theme.field.labelGap) / 2)

        function init() {
            UnitTheme.reset();
            root.written = [];
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function shown(item) {
            for (let at = item; at !== null; at = at.parent) if (!at.visible) return false;
            return true;
        }
        function sliderOf(item) { return descendants(item).find(child => String(child).indexOf("Slider") === 0 && shown(child)); }
        function inputOf(item) { return descendants(item).find(child => child instanceof TextInput && shown(child)); }
        // The error lines the field's rows draw.
        function errorsOf(item) {
            return descendants(item).filter(child => child.hintTone !== undefined && typeof child.error === "string" && child.error !== "" && shown(child)).map(child => child.error);
        }
        function hintOf(item) { return displayedTextItems(item).find(child => child.role === "hint" && displayedText(child) !== "" && shown(child)); }
        function make(spec, value) {
            const made = createTemporaryObject(numberField, root, { spec: spec, value: value });
            verify(made !== null);
            verify(waitForItemPolished(made));
            return made;
        }
        function enter(made, text) {
            const input = inputOf(made);
            input.forceActiveFocus();
            input.text = text;
            keyClick(Qt.Key_Return);
        }

        function test_the_editor_follows_the_step_count_data() {
            return [
                { tag: "at the limit", spec: () => ({ type: "number", label: "Count", min: 0, max: limit, step: 1 }), typed: false },
                { tag: "one step past the limit", spec: () => ({ type: "number", label: "Count", min: 0, max: limit + 1, step: 1 }), typed: true },
                { tag: "the weekly spend cap", spec: () => ({ type: "number", label: "Weekly OpenAI spend cap", min: 0, max: 10000, step: 1 }), typed: true },
                { tag: "a fine step over a short range", spec: () => ({ type: "number", label: "Speed", min: -1, max: 1, step: 0.05 }), typed: false },
                { tag: "no step", spec: () => ({ type: "number", label: "Level", min: 0, max: 10000 }), typed: false }
            ];
        }
        function test_the_editor_follows_the_step_count(data) {
            const made = make(data.spec(), 0);
            compare(sliderOf(made) === undefined, data.typed, "a slider only while each step has its room");
            compare(inputOf(made) !== undefined, data.typed, "a text field in the slider's place");
        }

        function test_a_typed_range_states_its_bounds_and_refuses_outside_them() {
            const made = make({ type: "number", label: "Weekly OpenAI spend cap", min: 0, max: 10000, step: 1 }, 25);
            verify(displayedText(hintOf(made)).indexOf("10,000") !== -1, "the hint names the range's grouped top");
            for (const text of ["10001", "-1", ""]) {
                enter(made, text);
                compare(root.written, [], text + ": nothing is written");
                compare(errorsOf(made).length, 1, text + ": an error line says why");
                verify(made.edited, text + ": the typed text stays");
                inputOf(made).text = "1";
                compare(errorsOf(made).length, 0, text + ": a new text clears the refusal");
            }
            enter(made, "10000");
            compare(root.written, [10000], "the top of the range is written");
            compare(errorsOf(made).length, 0);
            verify(!made.edited);
        }

        function test_a_custom_row_over_the_limit_is_a_text_field() {
            const made = make({ type: "number", label: "Lock after", min: 0, max: 86400, step: 30, unit: "seconds", allowCustom: true,
                presets: [{ value: 0, label: "Never" }, { value: 60 }] }, 450);
            verify(made.customVisible);
            compare(sliderOf(made), undefined, "no slider in the custom row");
            compare(inputOf(made).text, "450");
            enter(made, "90000");
            compare(root.written, [], "a time past the range is not written");
            compare(errorsOf(made).length, 1, "the custom row says why");
            enter(made, "600");
            compare(root.written, [600]);
        }
    }
}
